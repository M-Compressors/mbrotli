import Mbrotli.EncoderLength

/-! # The packed command-extra table preserves the RFC length classes

The encoder indexes this table with a command symbol whose insert and encoded
copy lengths belong to that symbol's RFC classes. The table stores bases and
widths only; actual length fields are subtracted when the command is written.
-/

open Aeneas Aeneas.Std Result
open Mbrotli.Rfc

namespace mbrotli
open shared.command

/-- The four fields packed into an entry of `COMMAND_EXTRAS`. -/
def commandExtrasPacked (i c : Nat) : Nat :=
  (row insertRows i).lo ||| ((row copyRows c).lo * 2 ^ 16) |||
    ((row insertRows i).extra * 2 ^ 32) |||
    (((row insertRows i).extra + (row copyRows c).extra) * 2 ^ 40)

/-- Every class pair fits its fields and all four fields survive extraction. -/
theorem commandExtrasPacked_fields : ∀ i < 24, ∀ c < 24,
    commandExtrasPacked i c < 2 ^ 64 ∧
    commandExtrasPacked i c % 2 ^ 16 = (row insertRows i).lo ∧
    commandExtrasPacked i c / 2 ^ 16 % 2 ^ 16 = (row copyRows c).lo ∧
    commandExtrasPacked i c / 2 ^ 32 % 32 = (row insertRows i).extra ∧
    commandExtrasPacked i c / 2 ^ 40 % 64 =
      (row insertRows i).extra + (row copyRows c).extra ∧
    (row insertRows i).extra ≤ 24 ∧ (row copyRows c).extra ≤ 24 := by
  decide +kernel

/-- Both length classes named by a valid command symbol are RFC classes. -/
theorem commandExtrasSymbolCodes : ∀ s < commandSymbols,
    insertCode s < 24 ∧ copyCode s < 24 := by
  decide +kernel

/-- Each individual base and width fits the field used by the initializer. -/
theorem commandExtrasParts_bounds : ∀ i < 24, ∀ c < 24,
    (row insertRows i).lo < 2 ^ 16 ∧ (row copyRows c).lo < 2 ^ 16 ∧
    (row insertRows i).extra ≤ 24 ∧ (row copyRows c).extra ≤ 24 := by
  decide +kernel

/-- Entries filled before the current insert/copy pair have their RFC fields. -/
def CommandExtrasReady (entries : Array U64 1024#usize) (i c : Nat) : Prop :=
  ∀ s, s < commandSymbols →
    (insertCode s < i ∨ insertCode s = i ∧ copyCode s < c) →
    entries[s]!.val = commandExtrasPacked (insertCode s) (copyCode s)

/-- No entry is required before the first pair is filled. -/
theorem CommandExtrasReady.initial (entries : Array U64 1024#usize) :
    CommandExtrasReady entries 0 0 := by
  intro s hs hdone
  omega

/-- Writing a symbol's own fields preserves every previously established entry. -/
theorem CommandExtrasReady.set (entries : Array U64 1024#usize) (i c : Nat)
    (index : Usize) (fields : U64) (hindex : index.val < commandSymbols)
    (hfields : fields.val = commandExtrasPacked (insertCode index.val) (copyCode index.val))
    (hready : CommandExtrasReady entries i c) :
    CommandExtrasReady (entries.set index fields) i c := by
  have := numBits_ge
  change index.val < 704 at hindex
  intro s hs hdone
  change s < 704 at hs
  by_cases heq : s = index.val
  · rw [Array.getElem!_Nat_set_eq _ _ _ _ ⟨heq.symm, by scalar_tac⟩]
    simpa only [heq] using hfields
  · rw [Array.getElem!_Nat_set_ne _ _ _ _ (Ne.symm heq)]
    exact hready s hs hdone

/-- Writing both distance forms completes the current insert/copy class pair. -/
theorem CommandExtrasReady.write_pair (entries : Array U64 1024#usize) (i c : Nat)
    (hi : i < 24) (hc : c < 24) (explicitIndex implicitIndex : Usize) (fields : U64)
    (he : explicitIndex.val = combineModel i c false)
    (hm : implicitIndex.val = combineModel i c true)
    (hf : fields.val = commandExtrasPacked i c)
    (hready : CommandExtrasReady entries i c) :
    CommandExtrasReady ((entries.set explicitIndex fields).set implicitIndex fields) i (c + 1) := by
  have := numBits_ge
  obtain ⟨helt, hei, hec, -⟩ := combineModel_rfc i hi c hc false
  obtain ⟨hmlt, hmi, hmc, -⟩ := combineModel_rfc i hi c hc true
  have he704 : combineModel i c false < 704 := helt
  have hm704 : combineModel i c true < 704 := hmlt
  have hfirst := CommandExtrasReady.set entries i c explicitIndex fields
    (by rw [he]; exact helt) (by simpa only [he, hei, hec] using hf) hready
  have hprevious := CommandExtrasReady.set (entries.set explicitIndex fields) i c implicitIndex fields
    (by rw [hm]; exact hmlt) (by simpa only [hm, hmi, hmc] using hf) hfirst
  intro s hs hdone
  have hs704 : s < 704 := hs
  by_cases hwas : insertCode s < i ∨ insertCode s = i ∧ copyCode s < c
  · exact hprevious s hs hwas
  · have his : insertCode s = i := by omega
    have hcs : copyCode s = c := by omega
    have hwhich : s = explicitIndex.val ∨ s = implicitIndex.val := by
      have inverse := combineModel_inverse s hs
      rw [his, hcs] at inverse
      cases h : implicitDistance s with
      | false => left; rw [he]; simpa only [h] using inverse.symm
      | true => right; rw [hm]; simpa only [h] using inverse.symm
    by_cases hit : s = implicitIndex.val
    · rw [Array.getElem!_Nat_set_eq _ _ _ _ ⟨hit.symm, by scalar_tac⟩]
      simpa only [his, hcs] using hf
    · have hse : s = explicitIndex.val := hwhich.resolve_right hit
      rw [Array.getElem!_Nat_set_ne _ _ _ _ (Ne.symm hit),
        Array.getElem!_Nat_set_eq _ _ _ _ ⟨hse.symm, by scalar_tac⟩]
      simpa only [his, hcs] using hf

/-- Completing all copy classes advances the outer insert-class loop. -/
theorem CommandExtrasReady.next_insert (entries : Array U64 1024#usize) (i : Nat)
    (hready : CommandExtrasReady entries i 24) :
    CommandExtrasReady entries (i + 1) 0 := by
  intro s hs hdone
  have hcodes := commandExtrasSymbolCodes s hs
  apply hready s hs
  omega

/-- After all insert classes, every valid symbol has its RFC fields. -/
theorem CommandExtrasReady.complete (entries : Array U64 1024#usize)
    (hready : CommandExtrasReady entries 24 0) :
    ∀ s, s < commandSymbols →
      entries[s]!.val = commandExtrasPacked (insertCode s) (copyCode s) := by
  intro s hs
  exact hready s hs (Or.inl (commandExtrasSymbolCodes s hs).1)

/-- The inner initializer loop fills every copy class of one insert class. -/
@[step]
theorem COMMAND_EXTRAS_loop0_loop0.spec
    (entries : Array U64 1024#usize) (insert copy : Usize)
    (hi : insert.val < 24) (hc : copy.val ≤ 24)
    (hready : CommandExtrasReady entries insert.val copy.val) :
    COMMAND_EXTRAS_loop0_loop0 entries insert copy
      ⦃ (t : Array U64 1024#usize) => CommandExtrasReady t insert.val 24 ⦄ := by
  have := numBits_ge
  unfold COMMAND_EXTRAS_loop0_loop0
  split
  · have hcopy : copy.val < 24 := by scalar_tac
    obtain ⟨hib, hcb, hix, hcx⟩ := commandExtrasParts_bounds insert.val hi copy.val hcopy
    obtain ⟨helt, hei, hec, -⟩ := combineModel_rfc insert.val hi copy.val hcopy false
    obtain ⟨hmlt, hmi, hmc, -⟩ := combineModel_rfc insert.val hi copy.val hcopy true
    have he704 : combineModel insert.val copy.val false < 704 := helt
    have hm704 : combineModel insert.val copy.val true < 704 := hmlt
    step as ⟨ ibase, hibase ⟩
    step as ⟨ ibase64, hibase64 ⟩
    have hibase64v : ibase64.val = (row insertRows insert.val).lo := by
      rw [hibase64, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), hibase]
    step as ⟨ cbase, hcbase ⟩
    step as ⟨ cbase64, hcbase64 ⟩
    have hcbase64v : cbase64.val = (row copyRows copy.val).lo := by
      rw [hcbase64, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), hcbase]
    step as ⟨ copyPart, hcopyPart ⟩
    have hcopyPartv : copyPart.val = (row copyRows copy.val).lo * 2 ^ 16 := by
      rw [hcopyPart, Nat.shiftLeft_eq, hcbase64v,
        show U64.size = 2 ^ 64 by simp [U64.size, U64.numBits]]
      exact Nat.mod_eq_of_lt (by omega)
    step as ⟨ bases, hbases ⟩
    step as ⟨ iextra, hiextra ⟩
    step as ⟨ iextra64, hiextra64 ⟩
    have hiextra64v : iextra64.val = (row insertRows insert.val).extra := by
      rw [hiextra64, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), hiextra]
    step as ⟨ insertPart, hinsertPart ⟩
    have hinsertPartv : insertPart.val = (row insertRows insert.val).extra * 2 ^ 32 := by
      rw [hinsertPart, Nat.shiftLeft_eq, hiextra64v,
        show U64.size = 2 ^ 64 by simp [U64.size, U64.numBits]]
      exact Nat.mod_eq_of_lt (by omega)
    step as ⟨ firstFields, hfirstFields ⟩
    step as ⟨ cextra, hcextra ⟩
    step as ⟨ total, htotal ⟩
    step as ⟨ total64, htotal64 ⟩
    have htotal64v : total64.val =
        (row insertRows insert.val).extra + (row copyRows copy.val).extra := by
      rw [htotal64, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac),
        htotal, hiextra, hcextra]
    step as ⟨ totalPart, htotalPart ⟩
    have htotalPartv : totalPart.val =
        ((row insertRows insert.val).extra + (row copyRows copy.val).extra) * 2 ^ 40 := by
      rw [htotalPart, Nat.shiftLeft_eq, htotal64v,
        show U64.size = 2 ^ 64 by simp [U64.size, U64.numBits]]
      exact Nat.mod_eq_of_lt (by omega)
    step as ⟨ fields, hfields ⟩
    have hfieldsv : fields.val = commandExtrasPacked insert.val copy.val := by
      rw [hfields, UScalar.val_or, hfirstFields, UScalar.val_or, hbases, UScalar.val_or,
        hibase64v, hcopyPartv, hinsertPartv, htotalPartv]
      rfl
    step as ⟨ i16, hi16 ⟩
    have hi16v : i16.val = insert.val := by
      rw [hi16, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    step as ⟨ c16, hc16 ⟩
    have hc16v : c16.val = copy.val := by
      rw [hc16, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    step as ⟨ explicitSymbol, hexplicitSymbol ⟩
    rw [hi16v, hc16v] at hexplicitSymbol
    step as ⟨ explicitIndex, hexplicitIndex ⟩
    have hev : explicitIndex.val = combineModel insert.val copy.val false := by
      rw [hexplicitIndex, UScalar.cast_val_eq,
        Nat.mod_eq_of_lt (lt_usize_pow _ (by scalar_tac)), hexplicitSymbol]
    step as ⟨ firstEntries, hfirstEntries ⟩
    step as ⟨ i16again, hi16again ⟩
    have hi16againv : i16again.val = insert.val := by
      rw [hi16again, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    step as ⟨ c16again, hc16again ⟩
    have hc16againv : c16again.val = copy.val := by
      rw [hc16again, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    step as ⟨ implicitSymbol, himplicitSymbol ⟩
    rw [hi16againv, hc16againv] at himplicitSymbol
    step as ⟨ implicitIndex, himplicitIndex ⟩
    have hmv : implicitIndex.val = combineModel insert.val copy.val true := by
      rw [himplicitIndex, UScalar.cast_val_eq,
        Nat.mod_eq_of_lt (lt_usize_pow _ (by scalar_tac)), himplicitSymbol]
    step as ⟨ allEntries, hallEntries ⟩
    step as ⟨ copy1, hcopy1 ⟩
    have hnext : CommandExtrasReady allEntries insert.val copy1.val := by
      rw [hcopy1, hallEntries, hfirstEntries]
      exact CommandExtrasReady.write_pair entries insert.val copy.val hi hcopy
        explicitIndex implicitIndex fields hev hmv hfieldsv hready
    apply WP.spec_mono (COMMAND_EXTRAS_loop0_loop0.spec allEntries insert copy1 hi
      (by scalar_tac) hnext)
    exact fun _ h => h
  · have heq : copy.val = 24 := by scalar_tac
    simp only [WP.spec_ok]
    simpa only [heq] using hready
termination_by 24 - copy.val
decreasing_by scalar_tac

/-- The outer initializer loop fills every insert class. -/
@[step]
theorem COMMAND_EXTRAS_loop0.spec (entries : Array U64 1024#usize) (insert : Usize)
    (hi : insert.val ≤ 24) (hready : CommandExtrasReady entries insert.val 0) :
    COMMAND_EXTRAS_loop0 entries insert
      ⦃ (t : Array U64 1024#usize) => CommandExtrasReady t 24 0 ⦄ := by
  have := numBits_ge
  unfold COMMAND_EXTRAS_loop0
  split
  · have hilt : insert.val < 24 := by scalar_tac
    step with COMMAND_EXTRAS_loop0_loop0.spec entries insert 0#usize hilt
      (by scalar_tac) hready as ⟨ entries1, hentries1 ⟩
    step as ⟨ insert1, hinsert1 ⟩
    have hnext : CommandExtrasReady entries1 insert1.val 0 := by
      rw [hinsert1]
      exact CommandExtrasReady.next_insert entries1 insert.val hentries1
    apply WP.spec_mono (COMMAND_EXTRAS_loop0.spec entries1 insert1 (by scalar_tac) hnext)
    exact fun _ h => h
  · have heq : insert.val = 24 := by scalar_tac
    simp only [WP.spec_ok]
    simpa only [heq] using hready
termination_by 24 - insert.val
decreasing_by scalar_tac

/-- Every valid symbol indexes exactly its RFC insert/copy bases and widths. -/
@[step]
theorem COMMAND_EXTRAS.spec :
    COMMAND_EXTRAS ⦃ (t : Array U64 1024#usize) =>
      ∀ s, s < commandSymbols →
        t[s]!.val = commandExtrasPacked (insertCode s) (copyCode s) ⦄ := by
  rw [COMMAND_EXTRAS]
  apply WP.spec_mono (COMMAND_EXTRAS_loop0.spec _ _ (by scalar_tac)
    (CommandExtrasReady.initial _))
  exact fun t ht => CommandExtrasReady.complete t ht

end mbrotli
