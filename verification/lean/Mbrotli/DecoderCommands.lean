import Mbrotli.LengthTables

/-! # The decoder's command table follows RFC 7932 section 5

`commands()` in `decompressor/core/stream.rs` precomputes, for every
insert-and-copy length symbol, what the decoder needs from it. Each entry is the
RFC's: the insert and copy codes the cell diagram assigns, their first lengths
and extra-bit counts, the implicit last-distance flag, and the distance context
section 7.2 derives from the copy length.
-/

open Aeneas Aeneas.Std Result
open Mbrotli.Rfc

namespace mbrotli
open decompressor.core.stream

/-- The packed cell value of block `k`, as `CELLS` stores it. -/
def cellValue (k : Nat) : Nat := (cells.getD k (0, 0)).1 + (cells.getD k (0, 0)).2 / 8

theorem cellValue_insert : ∀ k < 11, cellValue k &&& 24 = (cells.getD k (0, 0)).1 := by decide

theorem cellValue_copy : ∀ k < 11, cellValue k * 2 ^ 3 &&& 24 = (cells.getD k (0, 0)).2 := by decide

/-- Section 7.2 asks for the copy length, the table only has the copy code: a
code whose first length is at most four has no extra bits, so its length is
its first length, and every longer code starts above four. -/
theorem distanceContext_of_code (c len : Nat) (hc : c < 24)
    (hlo : (row copyRows c).lo ≤ len) (hhi : len ≤ (row copyRows c).hi) :
    distanceContext len = if (row copyRows c).lo > 4 then 3 else (row copyRows c).lo - 2 := by
  have h : ∀ c < 24, (row copyRows c).lo ≤ 4 → (row copyRows c).hi = (row copyRows c).lo := by decide
  have h2 : ∀ c < 24, 2 ≤ (row copyRows c).lo := by decide
  have := h2 c hc
  by_cases hl : (row copyRows c).lo ≤ 4
  · have := h c hc hl
    simp only [distanceContext]; grind
  · simp only [distanceContext]; grind

instance : Inhabited Command :=
  ⟨{ insert_extra := 0#u8, copy_extra := 0#u8, copy_code := 0#u8, distance_context := 0#u8,
     implicit := false, insert_base := 0#u16, copy_base := 0#u16 }⟩

/-- The entry RFC 7932 sections 5 and 7.2 prescribe for symbol `s`. -/
def Command.Rfc (s : Nat) (e : Command) : Prop :=
  e.insert_base.val = (row insertRows (insertCode s)).lo ∧
  e.insert_extra.val = (row insertRows (insertCode s)).extra ∧
  e.copy_base.val = (row copyRows (copyCode s)).lo ∧
  e.copy_extra.val = (row copyRows (copyCode s)).extra ∧
  e.copy_code.val = copyCode s ∧
  e.implicit = implicitDistance s ∧
  ∀ len, (row copyRows (copyCode s)).lo ≤ len → len ≤ (row copyRows (copyCode s)).hi →
    e.distance_context.val = distanceContext len

@[step]
theorem commands_loop.spec (table : Array Command 1024#usize) (symbol : Usize)
    (hs : symbol.val ≤ 704) (hdone : ∀ s < symbol.val, Command.Rfc s table[s]!) :
    commands_loop table symbol ⦃ (t : Array Command 1024#usize) =>
      ∀ s < 704, Command.Rfc s t[s]! ⦄ := by
  have := numBits_ge
  unfold commands_loop
  split
  · have hlt : symbol.val < 704 := by scalar_tac
    obtain ⟨hic, hcc⟩ := codes_lt symbol.val hlt
    step as ⟨ i, i_post ⟩
    have hi : i.val = symbol.val / 64 := by rw [i_post, Nat.shiftRight_eq_div_pow]
    have hi11 : i.val < 11 := by rw [hi]; agrind
    step as ⟨ cell, cell_post ⟩
    step as ⟨ i1, i1_post ⟩
    have hins0 : i1.val = (cells.getD (symbol.val / 64) (0, 0)).1 := by
      rw [i1_post, UScalar.val_and, cell_post, ← hi]; exact cellValue_insert _ hi11
    step as ⟨ i2, i2_post ⟩
    step as ⟨ i3, i3_post ⟩
    have hi3 : i3.val = symbol.val / 8 % 8 := by
      rw [i3_post, UScalar.val_and, i2_post, Nat.shiftRight_eq_div_pow]
      exact Nat.and_two_pow_sub_one_eq_mod _ 3
    have hcb : ∀ k < 11, (cells.getD k (0, 0)).1 ≤ 16 ∧ (cells.getD k (0, 0)).2 ≤ 16 := by decide
    have hcb' := hcb (symbol.val / 64) (by rw [← hi]; exact hi11)
    step as ⟨ ins, ins_post ⟩
    have hins : ins.val = insertCode symbol.val := by rw [ins_post, hins0, hi3]; rfl
    step as ⟨ i4, i4_post ⟩
    have hcell : cell.val < 32 := by
      rw [cell_post]; have : ∀ k < 11, cellValue k < 32 := by decide
      exact this _ hi11
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by have := usize_size_ge; agrind)] at i4_post
    step as ⟨ i5, i5_post ⟩
    have hcp0 : i5.val = (cells.getD (symbol.val / 64) (0, 0)).2 := by
      rw [i5_post, UScalar.val_and, i4_post, cell_post, ← hi]; exact cellValue_copy _ hi11
    step as ⟨ i6, i6_post ⟩
    have hi6 : i6.val = symbol.val % 8 := by
      rw [i6_post, UScalar.val_and]; exact Nat.and_two_pow_sub_one_eq_mod _ 3
    step as ⟨ copy, copy_post ⟩
    have hcp : copy.val = copyCode symbol.val := by rw [copy_post, hcp0, hi6]; rfl
    step as ⟨ copy_base, copy_base_post ⟩
    step as ⟨ i7, i7_post ⟩
    step as ⟨ i8, i8_post ⟩
    step as ⟨ i9, i9_post ⟩
    step as ⟨ i10, i10_post ⟩
    step as ⟨ i11, i11_post ⟩
    have hcpl : ∀ c < 24, 2 ≤ (row copyRows c).lo ∧ (row copyRows c).lo < 2 ^ 16 ∧
        (row copyRows c).extra < 2 ^ 8 ∧ (row insertRows c).lo < 2 ^ 16 ∧
        (row insertRows c).extra < 2 ^ 8 := by decide
    obtain ⟨hcl2, hcl16, hce8, -, -⟩ := hcpl copy.val (by rw [hcp]; exact hcc)
    obtain ⟨-, -, -, hil16, hie8⟩ := hcpl ins.val (by rw [hins]; exact hic)
    /- The distance context: `3` past a first length of four, the first length
       less two below. -/
    have hspec : (if copy_base > 4#u32 then ok 3#u8 else do
          let i13 ← copy_base - 2#u32
          ok (UScalar.cast .U8 i13)) ⦃ (ctx : U8) =>
        ctx.val = if (row copyRows copy.val).lo > 4 then 3 else (row copyRows copy.val).lo - 2 ⦄ := by
      split
      · have : (row copyRows copy.val).lo > 4 := by scalar_tac
        simp only [WP.spec_ok, show ((row copyRows copy.val).lo > 4) = True from eq_true this, ite_true]
        rfl
      · have : ¬ (row copyRows copy.val).lo > 4 := by scalar_tac
        step as ⟨ i13, i13_post ⟩
        simp only [show ((row copyRows copy.val).lo > 4) = False from eq_false this,
          ite_false]
        rw [UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), i13_post, copy_base_post]
    apply WP.spec_bind hspec
    intro ctx hctxv
    step as ⟨ i12, i12_post ⟩
    step as ⟨ i14, i14_post ⟩
    step as ⟨ i15, i15_post ⟩
    step as ⟨ a, a_post ⟩
    step as ⟨ symbol1, symbol1_post ⟩
    apply WP.spec_mono (commands_loop.spec a symbol1 (by scalar_tac) ?_)
    · exact fun _ h => h
    · intro s hs
      rw [a_post]
      by_cases hsym : s = symbol.val
      · rw [Array.getElem!_Nat_set_eq _ _ _ _ ⟨hsym.symm, by scalar_tac⟩, hsym]
        have h8 : ∀ x : U32, x.val < 2 ^ 8 → (UScalar.cast .U8 x).val = x.val := fun x h => by
          rw [UScalar.cast_val_eq]; exact Nat.mod_eq_of_lt h
        have h16 : ∀ x : U32, x.val < 2 ^ 16 → (UScalar.cast .U16 x).val = x.val := fun x h => by
          rw [UScalar.cast_val_eq]; exact Nat.mod_eq_of_lt h
        refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
        · show i14.val = _
          rw [i14_post, h16 _ (by rw [i12_post]; exact hil16), i12_post, hins]
        · show i8.val = _
          rw [i8_post, h8 _ (by rw [i7_post]; exact hie8), i7_post, hins]
        · show i15.val = _
          rw [i15_post, h16 _ (by rw [copy_base_post]; exact hcl16), copy_base_post, hcp]
        · show i10.val = _
          rw [i10_post, h8 _ (by rw [i9_post]; exact hce8), i9_post, hcp]
        · show i11.val = _
          rw [i11_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), hcp]
        · show decide (symbol < 128#usize) = implicitDistance symbol.val
          simp only [implicitDistance]
          scalar_tac
        · intro len hlo hhi
          show ctx.val = _
          rw [hctxv, hcp, distanceContext_of_code _ len hcc hlo hhi]
      · rw [Array.getElem!_Nat_set_ne _ _ _ _ (Ne.symm hsym)]
        exact hdone s (by scalar_tac)
  · have : symbol.val = 704 := by scalar_tac
    rw [this] at hdone
    simp only [WP.spec_ok]
    exact hdone
termination_by 704 - symbol.val
decreasing_by scalar_decr_tac

/-- **Spec theorem for `mbrotli::decompressor::core::stream::commands`**
Every entry of the decoder's command table for the 704 insert-and-copy length
symbols is the one RFC 7932 sections 5 and 7.2 prescribe. -/
@[step]
theorem commands.spec :
    commands ⦃ (t : Array Command 1024#usize) => ∀ s < 704, Command.Rfc s t[s]! ⦄ := by
  unfold commands
  exact commands_loop.spec _ _ (by scalar_tac) (fun _ h => absurd h (by scalar_tac))

end mbrotli
