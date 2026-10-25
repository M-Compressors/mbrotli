import Mbrotli.LengthTables

/-! # The encoder's length codes follow RFC 7932 section 5

`insert_length_code` and `copy_length_code` in `shared/command.rs` pick, for
every length the format can carry, the code whose printed range holds it.
-/

open Aeneas Aeneas.Std Result
open Mbrotli.Rfc

namespace mbrotli
open shared.command

attribute [local simp, local scalar_tac_simps] Nat.one_shiftLeft Nat.shiftLeft_eq
  Nat.shiftRight_eq_div_pow

/-- The leading bit of a non-zero `m` brackets it between two powers of two. -/
theorem log_bracket (m : Nat) (hm : m ≠ 0) : 2 ^ Nat.log 2 m ≤ m ∧ m < 2 ^ (Nat.log 2 m + 1) :=
  ⟨Nat.pow_log_le_self 2 hm, Nat.lt_pow_succ_log_self (by decide) m⟩

/-- Insert codes 6 to 15 come in pairs per bucket: code `2k + q` for `q ∈ {2, 3}`
covers `2 + q · 2^(k-1)` up, with `k - 1` extra bits. -/
theorem insertRows_middle : ∀ k < 7, 2 ≤ k → ∀ q < 4, 2 ≤ q →
    row insertRows (2 * (k - 1) + q + 2) = ⟨k - 1, 2 + q * 2 ^ (k - 1), 1 + (q + 1) * 2 ^ (k - 1)⟩ := by
  decide

/-- Insert codes 16 to 20 cover `66 + 2^k` up, with `k` extra bits. -/
theorem insertRows_upper : ∀ k < 11, 6 ≤ k →
    row insertRows (k + 10) = ⟨k, 66 + 2 ^ k, 65 + 2 ^ (k + 1)⟩ := by
  decide

/-- **Spec theorem for `mbrotli::shared::command::insert_length_code`**
The code whose RFC range holds `insertlen`, for every insert length the format
can carry. -/
@[step]
theorem insert_length_code.spec (insertlen : Usize) (h : insertlen.val ≤ 16799809) :
    insert_length_code insertlen ⦃ (code : U16) =>
      code.val < 24 ∧ (row insertRows code.val).lo ≤ insertlen.val ∧
      insertlen.val ≤ (row insertRows code.val).hi ⦄ := by
  have := numBits_ge
  unfold insert_length_code
  split
  · /- Codes 0 to 5 are the lengths themselves. -/
    have : ∀ c < 6, row insertRows c = ⟨0, c, c⟩ := by decide
    have hv : (UScalar.cast .U16 insertlen).val = insertlen.val := by
      rw [UScalar.cast_val_eq]; exact Nat.mod_eq_of_lt (by scalar_tac)
    have hr := this insertlen.val (by scalar_tac)
    simp only [WP.spec_ok, hv, hr]
    scalar_tac
  · split
    · step as ⟨ i, i_post ⟩
      have hm0 : i.val ≠ 0 := by scalar_tac
      step as ⟨ i1, i1_post ⟩
      obtain ⟨hk1, hk2⟩ := log_bracket i.val hm0
      rw [← i1_post] at hk1 hk2
      have hk2' : 2 ≤ i1.val := by
        by_contra hc
        have : 2 ^ (i1.val + 1) ≤ 2 ^ 2 := Nat.pow_le_pow_right (by decide) (by agrind)
        scalar_tac
      have hk6 : i1.val ≤ 6 := by
        by_contra hc
        have : 2 ^ 7 ≤ 2 ^ i1.val := Nat.pow_le_pow_right (by decide) (by agrind)
        scalar_tac
      step as ⟨ nbits, nbits_post ⟩
      step as ⟨ i2, i2_post ⟩
      step as ⟨ i3, i3_post ⟩
      step as ⟨ i4, i4_post ⟩
      step as ⟨ i5, i5_post ⟩
      have hi4 : i4.val = i.val := by
        rw [i4_post, i3_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), i_post]
      have hnb : nbits.val + 1 = i1.val := by agrind
      have hP : 0 < 2 ^ nbits.val := Nat.two_pow_pos _
      have hpow : 2 ^ i1.val = 2 * 2 ^ nbits.val := by rw [← hnb, Nat.pow_succ]; ring
      have hpow1 : 2 ^ (i1.val + 1) = 4 * 2 ^ nbits.val := by rw [← hnb, Nat.pow_succ, Nat.pow_succ]; ring
      have hq : i5.val = i.val / 2 ^ nbits.val := by rw [i5_post, Nat.shiftRight_eq_div_pow, hi4]
      have hq2 : 2 ≤ i5.val := by rw [hq]; exact (Nat.le_div_iff_mul_le hP).2 (by agrind)
      have hq4 : i5.val < 4 := by rw [hq]; exact (Nat.div_lt_iff_lt_mul hP).2 (by agrind)
      have hlo : i5.val * 2 ^ nbits.val ≤ i.val := by rw [hq]; exact Nat.div_mul_le_self _ _
      have hhi : i.val < (i5.val + 1) * 2 ^ nbits.val := by
        rw [hq, Nat.mul_comm]; exact Nat.lt_mul_div_succ _ hP
      have hrow := insertRows_middle i1.val (by agrind) hk2' i5.val hq4 hq2
      have hi2 : i2.val = 2 * nbits.val := by
        rw [i2_post, Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by scalar_tac)]; ring
      step as ⟨ i6, i6_post ⟩
      step as ⟨ i7, i7_post ⟩
      have hcode : (UScalar.cast .U16 i7).val = 2 * (i1.val - 1) + i5.val + 2 := by
        rw [UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), i7_post, i6_post, hi2]; agrind
      simp only [hcode, hrow]
      have : i1.val - 1 = nbits.val := by agrind
      rw [this]
      refine ⟨by agrind, by agrind, by agrind⟩
    · split
      · step as ⟨ i, i_post ⟩
        have hm0 : i.val ≠ 0 := by scalar_tac
        step as ⟨ i1, i1_post ⟩
        obtain ⟨hk1, hk2⟩ := log_bracket i.val hm0
        rw [← i1_post] at hk1 hk2
        have hk6 : 6 ≤ i1.val := by
          by_contra hc
          have : 2 ^ (i1.val + 1) ≤ 2 ^ 6 := Nat.pow_le_pow_right (by decide) (by agrind)
          scalar_tac
        have hk10 : i1.val ≤ 10 := by
          by_contra hc
          have : 2 ^ 11 ≤ 2 ^ i1.val := Nat.pow_le_pow_right (by decide) (by agrind)
          scalar_tac
        have hrow := insertRows_upper i1.val (by agrind) hk6
        have hpow : 2 ^ (i1.val + 1) = 2 * 2 ^ i1.val := by rw [Nat.pow_succ]; ring
        step as ⟨ i2, i2_post ⟩
        have hcode : (UScalar.cast .U16 i2).val = i1.val + 10 := by
          rw [UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), i2_post]
        simp only [hcode, hrow]
        refine ⟨by agrind, by agrind, by agrind⟩
      · have h21 : row insertRows 21 = ⟨12, 2114, 6209⟩ := by decide
        have h22 : row insertRows 22 = ⟨14, 6210, 22593⟩ := by decide
        have h23 : row insertRows 23 = ⟨24, 22594, 16799809⟩ := by decide
        split
        · simp only [WP.spec_ok]
          show 21 < 24 ∧ (row insertRows 21).lo ≤ _ ∧ _ ≤ (row insertRows 21).hi
          rw [h21]; scalar_tac
        · split
          · simp only [WP.spec_ok]
            show 22 < 24 ∧ (row insertRows 22).lo ≤ _ ∧ _ ≤ (row insertRows 22).hi
            rw [h22]; scalar_tac
          · simp only [WP.spec_ok]
            show 23 < 24 ∧ (row insertRows 23).lo ≤ _ ∧ _ ≤ (row insertRows 23).hi
            rw [h23]; scalar_tac

/-- `c` is the copy code of length `l` (RFC 7932, section 5). -/
def CopyCodeOf (l c : Nat) : Prop := c < 24 ∧ (row copyRows c).lo ≤ l ∧ l ≤ (row copyRows c).hi

theorem copyRows_facts :
    (∀ c < 23, (row copyRows c).lo ≤ (row copyRows c).hi) ∧ (row copyRows 23).lo = 2118 ∧
    (∀ c < 24, (row copyRows c).lo < 2118 → c < 23) := by decide

/-- The loop that fills `COPY_LENGTH_CODES`: `code` is the code of `length`,
and every length already written holds its own code. -/
@[step]
theorem COPY_LENGTH_CODES_loop.spec (codes : Array U8 2118#usize) (length code : Usize)
    (h2 : 2 ≤ length.val) (hl : length.val ≤ 2118) (hc : code.val < 23)
    (hlo : (row copyRows code.val).lo ≤ length.val)
    (hhi : length.val ≤ (row copyRows (code.val + 1)).lo)
    (hdone : ∀ l, 2 ≤ l → l < length.val → CopyCodeOf l codes[l]!.val) :
    COPY_LENGTH_CODES_loop codes length code ⦃ (t : Array U8 2118#usize) =>
      ∀ l, 2 ≤ l → l < 2118 → CopyCodeOf l t[l]!.val ⦄ := by
  have := numBits_ge
  obtain ⟨hlh, h23, hlt23⟩ := copyRows_facts
  have hcont := copyRows_contiguous
  unfold COPY_LENGTH_CODES_loop
  step as ⟨ sl, sl_post ⟩
  split
  · have hlen : length.val < 2118 := by scalar_tac
    step as ⟨ i1, i1_post ⟩
    step as ⟨ i2, i2_post ⟩
    step as ⟨ i3, i3_post ⟩
    have hi3 : i3.val = (row copyRows (code.val + 1)).lo := by
      rw [i3_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (lt_usize_pow _ (by scalar_tac)), i2_post,
        i1_post]
    have hset : ∀ (c : Usize) (a : Array U8 2118#usize), c.val < 24 → CopyCodeOf length.val c.val →
        a = codes.set length (UScalar.cast .U8 c) →
        ∀ l, 2 ≤ l → l < length.val + 1 → CopyCodeOf l a[l]!.val := by
      intro c a hc24 hok ha l hl2 hl
      rw [ha]
      by_cases hle : l = length.val
      · rw [Array.getElem!_Nat_set_eq _ _ _ _ ⟨hle.symm, by scalar_tac⟩, UScalar.cast_val_eq,
          Nat.mod_eq_of_lt (by scalar_tac), hle]
        exact hok
      · rw [Array.getElem!_Nat_set_ne _ _ _ _ (Ne.symm hle)]
        exact hdone l hl2 (by agrind)
    split
    · /- `length` starts the next code. -/
      have heq : length.val = (row copyRows (code.val + 1)).lo := by scalar_tac
      have hc23 : code.val + 1 < 23 := hlt23 _ (by agrind) (by agrind)
      have hcn := hcont (code.val + 1) (by agrind)
      have hok : CopyCodeOf length.val i1.val := ⟨by agrind, by agrind, by agrind⟩
      step as ⟨ i4, i4_post ⟩
      step as ⟨ a, a_post ⟩
      step as ⟨ length1, length1_post ⟩
      have hl1 := hlh (code.val + 1) hc23
      apply WP.spec_mono (COPY_LENGTH_CODES_loop.spec a length1 i1 (by agrind) (by agrind) (by agrind)
        (by agrind) (by agrind)
        (by rw [length1_post]; exact hset i1 a (by agrind) hok (by rw [a_post, i4_post])))
      exact fun _ h => h
    · /- `length` stays in the current code. -/
      have hcn := hcont code.val hc
      have hok : CopyCodeOf length.val code.val := ⟨by agrind, by agrind, by agrind⟩
      step as ⟨ i4, i4_post ⟩
      step as ⟨ a, a_post ⟩
      step as ⟨ length1, length1_post ⟩
      apply WP.spec_mono (COPY_LENGTH_CODES_loop.spec a length1 code (by agrind) (by agrind) hc
        (by agrind) (by agrind)
        (by rw [length1_post]; exact hset code a (by agrind) hok (by rw [a_post, i4_post])))
      exact fun _ h => h
  · simp only [step_simps]
    agrind
termination_by 2118 - length.val
decreasing_by
  · agrind
  · agrind

/-- **Spec theorem for `mbrotli::shared::command::COPY_LENGTH_CODES`**
Entry `l` of the table is the copy code of length `l`, for `2 ≤ l < 2118`. -/
@[step]
theorem COPY_LENGTH_CODES.spec :
    COPY_LENGTH_CODES ⦃ (t : Array U8 2118#usize) =>
      ∀ l, 2 ≤ l → l < 2118 → CopyCodeOf l t[l]!.val ⦄ := by
  rw [COPY_LENGTH_CODES]
  exact COPY_LENGTH_CODES_loop.spec _ _ _ (by scalar_tac) (by scalar_tac) (by scalar_tac)
    (by decide) (by decide) (fun _ h1 h2 => absurd h2 (by scalar_tac))

/-- **Spec theorem for `mbrotli::shared::command::copy_length_code`**
The code whose RFC range holds `copylen`, for every copy length the format can
carry. -/
@[step]
theorem copy_length_code.spec (copylen : Usize) (h2 : 2 ≤ copylen.val)
    (h : copylen.val ≤ 16779333) :
    copy_length_code copylen ⦃ (code : U16) => CopyCodeOf copylen.val code.val ⦄ := by
  have := numBits_ge
  unfold copy_length_code
  split
  · have : ∀ c < 8, row copyRows c = ⟨0, c + 2, c + 2⟩ := by decide
    step as ⟨ i, i_post ⟩
    have hv : (UScalar.cast .U16 i).val = copylen.val - 2 := by
      rw [UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), i_post]
    have hr := this (copylen.val - 2) (by scalar_tac)
    simp only [CopyCodeOf, hv, hr]
    scalar_tac
  · step as ⟨ a, a_post ⟩
    step as ⟨ sl, sl_post ⟩
    split
    · step as ⟨ i1, i1_post ⟩
      have hlt : copylen.val < 2118 := by scalar_tac
      have hi1 : i1 = a[copylen.val]! := by
        rw [i1_post, Array.getElem!_Nat_eq, List.Inhabited_getElem_eq_getElem!]
        scalar_tac
      have hv : (UScalar.cast .U16 i1).val = i1.val := by
        rw [UScalar.cast_val_eq]; exact Nat.mod_eq_of_lt (by scalar_tac)
      rw [hv, hi1]
      exact a_post _ h2 hlt
    · have h23 : row copyRows 23 = ⟨24, 2118, 16779333⟩ := by decide
      simp only [WP.spec_ok]
      show 23 < 24 ∧ (row copyRows 23).lo ≤ _ ∧ _ ≤ (row copyRows 23).hi
      rw [h23]; scalar_tac

/-! ## Insert-and-copy length symbols -/

/-- The block the encoder computes for a symbol outside the implicit-distance
cells: `0x40` per cell row step, with the cell order of RFC 7932 section 5
packed into the constant `0x520D40`. -/
def offsetModel (i c : Nat) : Nat :=
  let off := 2 * (c / 8 + 3 * (i / 8))
  off * 32 + 64 + ((5377344 >>> off) &&& 192)

/-- What `combine_length_codes` computes, over natural numbers. -/
def combineModel (i c : Nat) (uld : Bool) : Nat :=
  let low := c % 8 + i % 8 * 8
  if uld && decide (i < 8) && decide (c < 16) then (if c < 8 then low else low + 64)
  else offsetModel i c + low

theorem offsetModel_facts : ∀ i < 24, ∀ c < 24, offsetModel i c % 64 = 0 ∧ offsetModel i c < 2 ^ 16 := by
  decide +kernel

/-- The symbol the encoder builds sits in the cell of the RFC diagram for its
two codes, and is implicit exactly when the caller asked for it and the codes
allow it. -/
theorem combineModel_rfc : ∀ i < 24, ∀ c < 24, ∀ uld : Bool,
    combineModel i c uld < commandSymbols ∧ insertCode (combineModel i c uld) = i ∧
    copyCode (combineModel i c uld) = c ∧
    implicitDistance (combineModel i c uld) = (uld && decide (i < 8) && decide (c < 16)) := by
  decide +kernel

/-- Every symbol is the one the encoder builds from its own codes and flag: the
cell diagram is a bijection. -/
theorem combineModel_inverse : ∀ s < commandSymbols,
    combineModel (insertCode s) (copyCode s) (implicitDistance s) = s := by
  decide +kernel

/-- The cell offset block, which `combine_length_codes` repeats on each path to a
non-implicit symbol. -/
theorem offset_block.spec (inscode copycode low : U16) (hi : inscode.val < 24)
    (hc : copycode.val < 24) (hl : low.val < 64) :
    (do
      let i3 ← lift (UScalar.cast .U32 copycode)
      let i4 ← i3 >>> 3#i32
      let i5 ← lift (UScalar.cast .U32 inscode)
      let i6 ← i5 >>> 3#i32
      let i7 ← 3#u32 * i6
      let i8 ← i4 + i7
      let offset ← 2#u32 * i8
      let i9 ← offset <<< 5#i32
      let i10 ← i9 + 64#u32
      let i11 ← 5377344#u32 >>> offset
      let i12 ← lift (i11 &&& 192#u32)
      let offset1 ← i10 + i12
      let i13 ← lift (UScalar.cast .U16 offset1)
      ok (i13 ||| low) : Result U16) ⦃ (r : U16) =>
        r.val = offsetModel inscode.val copycode.val + low.val ⦄ := by
  obtain ⟨hmod, hlt⟩ := offsetModel_facts _ hi _ hc
  have h32 : ∀ x : U16, (UScalar.cast .U32 x).val = x.val := fun x => by
    rw [UScalar.cast_val_eq]; exact Nat.mod_eq_of_lt (by scalar_tac)
  step as ⟨ i3, i3_post ⟩
  step as ⟨ i4, i4_post ⟩
  step as ⟨ i5, i5_post ⟩
  step as ⟨ i6, i6_post ⟩
  step as ⟨ i7, i7_post ⟩
  step as ⟨ i8, i8_post ⟩
  step as ⟨ offset, offset_post ⟩
  have hoff : offset.val = 2 * (copycode.val / 8 + 3 * (inscode.val / 8)) := by
    rw [offset_post, i8_post, i7_post, i6_post, i4_post, i5_post, i3_post, h32, h32]
    simp only [Nat.shiftRight_eq_div_pow]
  step as ⟨ i9, i9_post ⟩
  step as ⟨ i10, i10_post ⟩
  step as ⟨ i11, i11_post ⟩
  step as ⟨ i12, i12_post ⟩
  have hsum : i10.val + i12.val = offsetModel inscode.val copycode.val := by
    rw [i10_post, i9_post, i12_post, UScalar.val_and, i11_post, hoff]
    simp only [offsetModel, Nat.shiftLeft_eq]
    rw [Nat.mod_eq_of_lt (by scalar_tac)]
    norm_num
  step as ⟨ offset1, offset1_post ⟩
  step as ⟨ i13, i13_post ⟩
  have h13 : i13.val = offsetModel inscode.val copycode.val := by
    rw [i13_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), offset1_post, hsum]
  rw [UScalar.val_or, h13]
  have hsplit : offsetModel inscode.val copycode.val = (offsetModel inscode.val copycode.val / 64) <<< 6 := by
    rw [Nat.shiftLeft_eq]; have := Nat.div_add_mod (offsetModel inscode.val copycode.val) 64; agrind
  rw [hsplit, ← Nat.shiftLeft_add_eq_or_of_lt (lt_of_lt_of_eq hl (by norm_num))]

/-- **Spec theorem for `mbrotli::shared::command::combine_length_codes`**
The symbol of the RFC cell for the two codes; see `combineModel_rfc`. -/
@[step]
theorem combine_length_codes.spec (inscode copycode : U16) (use_last_distance : Bool)
    (hi : inscode.val < 24) (hc : copycode.val < 24) :
    combine_length_codes inscode copycode use_last_distance ⦃ (r : U16) =>
      r.val = combineModel inscode.val copycode.val use_last_distance ⦄ := by
  have := numBits_ge
  unfold combine_length_codes
  step as ⟨ i, i_post ⟩
  step as ⟨ i1, i1_post ⟩
  step as ⟨ i2, i2_post ⟩
  step as ⟨ low, low_post ⟩
  have hiv : i.val = copycode.val % 8 := by
    have := i_post; simp only [UScalar.val_and] at this
    rw [this]; exact Nat.and_two_pow_sub_one_eq_mod _ 3
  have hi1v : i1.val = inscode.val % 8 := by
    have := i1_post; simp only [UScalar.val_and] at this
    rw [this]; exact Nat.and_two_pow_sub_one_eq_mod _ 3
  have hi2 : i2.val = (inscode.val % 8) <<< 3 := by
    rw [i2_post, hi1v, Nat.mod_eq_of_lt]
    rw [Nat.shiftLeft_eq]
    have : inscode.val % 8 < 8 := Nat.mod_lt _ (by decide)
    have : (2 : Nat) ^ 3 = 8 := by norm_num
    have : U16.size = 2 ^ 16 := by simp [U16.size, U16.numBits]
    agrind
  have hlow : low.val = copycode.val % 8 + inscode.val % 8 * 8 := by
    rw [low_post, UScalar.val_or, hiv, hi2, Nat.lor_comm,
      ← Nat.shiftLeft_add_eq_or_of_lt (Nat.mod_lt _ (by decide)), Nat.shiftLeft_eq]
    agrind
  have hl64 : low.val < 64 := by rw [hlow]; agrind
  have hoff : ∀ uld : Bool, ¬ (uld && decide (inscode.val < 8) && decide (copycode.val < 16)) = true →
      (offsetModel inscode.val copycode.val + low.val = combineModel inscode.val copycode.val uld) := by
    intro uld h
    simp only [combineModel, h, ite_false, Bool.false_eq_true, hlow]
  have hblock : ¬ (use_last_distance && decide (inscode.val < 8) && decide (copycode.val < 16)) = true →
      (do
        let i3 ← lift (UScalar.cast .U32 copycode)
        let i4 ← i3 >>> 3#i32
        let i5 ← lift (UScalar.cast .U32 inscode)
        let i6 ← i5 >>> 3#i32
        let i7 ← 3#u32 * i6
        let i8 ← i4 + i7
        let offset ← 2#u32 * i8
        let i9 ← offset <<< 5#i32
        let i10 ← i9 + 64#u32
        let i11 ← 5377344#u32 >>> offset
        let i12 ← lift (i11 &&& 192#u32)
        let offset1 ← i10 + i12
        let i13 ← lift (UScalar.cast .U16 offset1)
        ok (i13 ||| low) : Result U16) ⦃ (r : U16) =>
          r.val = combineModel inscode.val copycode.val use_last_distance ⦄ := fun h =>
    WP.spec_mono (offset_block.spec inscode copycode low hi hc hl64)
      (fun r hr => by rw [hr]; exact hoff _ h)
  split
  · split
    · split
      · /- An implicit-distance cell. -/
        have hcond : (use_last_distance && decide (inscode.val < 8) && decide (copycode.val < 16)) = true := by
          simp only [Bool.and_eq_true, decide_eq_true_eq]; agrind
        split
        · rename_i h8
          have hc8 : copycode.val < 8 := (UScalar.lt_equiv _ _).mp h8
          simp only [WP.spec_ok, combineModel, hcond, ite_true, hlow, hc8]
        · rename_i h8
          have hc8 : ¬ copycode.val < 8 := fun h => h8 ((UScalar.lt_equiv _ _).mpr h)
          simp only [WP.spec_ok, combineModel, hcond, ite_true, hc8, ite_false]
          rw [UScalar.val_or, Nat.lor_comm,
            show (64#u16 : U16).val = 1 <<< 6 by rfl,
            ← Nat.shiftLeft_add_eq_or_of_lt (lt_of_lt_of_eq hl64 (by norm_num)), hlow]
          rw [Nat.one_shiftLeft]; agrind
      · exact hblock (by simp only [Bool.and_eq_true, decide_eq_true_eq]; agrind)
    · exact hblock (by simp only [Bool.and_eq_true, decide_eq_true_eq]; agrind)
  · exact hblock (by simp only [Bool.and_eq_true, decide_eq_true_eq]; agrind)

/-- `c` is the insert code of length `l` (RFC 7932, section 5). -/
def InsertCodeOf (l c : Nat) : Prop := c < 24 ∧ (row insertRows c).lo ≤ l ∧ l ≤ (row insertRows c).hi

/-- **Spec theorem for `mbrotli::shared::command::length_code`**
The insert-and-copy length symbol for an insert and a copy length: the RFC cell
of their codes, implicit exactly when asked for and allowed. -/
@[step]
theorem length_code.spec (insertlen copylen : Usize) (use_last_distance : Bool)
    (hi : insertlen.val ≤ 16799809) (h2 : 2 ≤ copylen.val) (hc : copylen.val ≤ 16779333) :
    length_code insertlen copylen use_last_distance ⦃ (s : U16) =>
      s.val < commandSymbols ∧ InsertCodeOf insertlen.val (insertCode s.val) ∧
      CopyCodeOf copylen.val (copyCode s.val) ∧
      implicitDistance s.val = (use_last_distance && decide (insertCode s.val < 8) &&
        decide (copyCode s.val < 16)) ⦄ := by
  unfold length_code
  step as ⟨ i, hi24, hilo, hihi ⟩
  step as ⟨ c, c_post ⟩
  step as ⟨ s, s_post ⟩
  obtain ⟨hlt, hins, hcp, himp⟩ := combineModel_rfc i.val hi24 c.val c_post.1 use_last_distance
  rw [s_post, hins, hcp]
  exact ⟨hlt, ⟨hi24, hilo, hihi⟩, c_post, himp⟩

end mbrotli
