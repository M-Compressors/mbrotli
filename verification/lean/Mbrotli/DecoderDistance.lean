import Mbrotli.Basic
import Mbrotli.Model

/-! # The decoder's distance arithmetic

Specifications of `mbrotli::decompressor::core::distance`: for every symbol of
the alphabet a layout declares and every extra field of the width that symbol
reads, the arithmetic neither panics nor overflows, and it computes the RFC 7932
distance `Mbrotli.Model.decode`.
-/

open Aeneas Aeneas.Std Result

namespace mbrotli
open decompressor.core.distance

/- Shifts and masks by a variable amount, restated as the arithmetic they
   perform, so that `step` can discharge the overflow side conditions. -/
attribute [local simp, local scalar_tac_simps] Nat.one_shiftLeft Nat.shiftLeft_eq
  Nat.shiftRight_eq_div_pow Nat.and_two_pow_sub_one_eq_mod Nat.and_one_is_mod

/-- The extra-bit width of a symbol inside an alphabet of `2 * n` buckets. -/
theorem width_le (p nd sym n : Nat) (h16 : 16 + nd ≤ sym) (hs : sym < 16 + nd + 2 * n * 2 ^ p) :
    Mbrotli.Model.width p nd sym ≤ n ∧ 1 ≤ Mbrotli.Model.width p nd sym := by
  have hlt : ¬ sym < 16 + nd := by agrind
  simp only [Mbrotli.Model.width, hlt, ite_false]
  have hP : 0 < 2 ^ (p + 1) := Nat.two_pow_pos _
  have : (sym - 16 - nd) / 2 ^ (p + 1) < n := by
    rw [Nat.div_lt_iff_lt_mul hP, Nat.pow_succ]; agrind
  agrind


@[step]
theorem DistanceLayout.extra_bits.spec (self : DistanceLayout) (symbol : Usize)
    (hp : self.postfix.val ≤ 3) (hd : self.direct.val ≤ 120) (hs : symbol.val < 2048) :
    self.extra_bits symbol ⦃ (r : U32) =>
      r.val = Mbrotli.Model.width self.postfix.val self.direct.val symbol.val ⦄ := by
  have := numBits_ge
  unfold DistanceLayout.extra_bits
  step as ⟨ i, i_post ⟩
  split
  · simp only [Mbrotli.Model.width]; agrind
  · step as ⟨ i1, i1_post ⟩
    step as ⟨ i2, i2_post ⟩
    step as ⟨ i3, i3_post ⟩
    step as ⟨ i4, i4_post ⟩
    have h4 : i4.val ≤ i2.val := by rw [i4_post]; exact Nat.shiftRight_le _ _
    step as ⟨ i5, i5_post ⟩
    have hlt : ¬ symbol.val < 16 + self.direct.val := by scalar_tac
    rw [UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    simp only [Mbrotli.Model.width, hlt, ite_false]
    simp only [Nat.shiftRight_eq_div_pow] at i4_post
    agrind


@[step]
theorem DistanceLayout.short_window_distance.spec (self : DistanceLayout) (symbol : Usize) (extra : U64)
    (hp : self.postfix.val ≤ 3) (hd : self.direct.val ≤ 120)
    (hs16 : 16 ≤ symbol.val) (hs : symbol.val < 16 + self.direct.val + 2 * 24 * 2 ^ self.postfix.val)
    (hx : extra.val < 2 ^ Mbrotli.Model.width self.postfix.val self.direct.val symbol.val) :
    self.short_window_distance symbol extra ⦃ (r : U64) =>
      r.val = Mbrotli.Model.decode self.postfix.val self.direct.val symbol.val extra.val ⦄ := by
  have := numBits_ge
  have hP8 : 2 ^ self.postfix.val ≤ 8 := by
    calc 2 ^ self.postfix.val ≤ 2 ^ 3 := Nat.pow_le_pow_right (by decide) hp
      _ = 8 := by norm_num
  have hP1 : 1 ≤ 2 ^ self.postfix.val := Nat.one_le_two_pow
  unfold DistanceLayout.short_window_distance
  step as ⟨ i, i_post ⟩
  split
  · /- A direct code: the distance is the symbol past the short codes. -/
    step as ⟨ i1, i1_post ⟩
    step as ⟨ i2, i2_post ⟩
    have hlt : symbol.val < 16 + self.direct.val := by scalar_tac
    rw [UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    simp only [Mbrotli.Model.decode, hlt, ite_true]
    agrind
  · have hlt : ¬ symbol.val < 16 + self.direct.val := by scalar_tac
    obtain ⟨hw, hw1⟩ := width_le self.postfix.val self.direct.val symbol.val 24 (by agrind) hs
    step as ⟨ i1, i1_post ⟩
    step as ⟨ code, code_post ⟩
    step as ⟨ high, high_post ⟩
    step as ⟨ i2, i2_post ⟩
    rw [Nat.one_shiftLeft, Nat.mod_eq_of_lt (two_pow_lt_usize _ (by agrind))] at i2_post
    step as ⟨ i3, i3_post ⟩
    step as ⟨ low, low_post ⟩
    step as ⟨ i4, i4_post ⟩
    step as ⟨ i5, i5_post ⟩
    step as ⟨ i6, i6_post ⟩
    step as ⟨ i7, i7_post ⟩
    have hlow : low.val = code.val % 2 ^ self.postfix.val := by
      rw [low_post, UScalar.val_and, i3_post, i2_post, Nat.and_two_pow_sub_one_eq_mod]
    have hi4 : i4.val = code.val / 2 ^ self.postfix.val % 2 := by
      rw [i4_post, UScalar.val_and, high_post, Nat.shiftRight_eq_div_pow]
      simp [Nat.and_one_is_mod]
    have hi6 : i6.val = 2 + code.val / 2 ^ self.postfix.val % 2 := by
      rw [i6_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]; agrind
    have hpw : 2 ^ i7.val ≤ 2 ^ 24 := Nat.pow_le_pow_right (by decide) (by agrind)
    have hpw1 : 2 ≤ 2 ^ i7.val := by
      calc 2 = 2 ^ 1 := by norm_num
        _ ≤ 2 ^ i7.val := Nat.pow_le_pow_right (by decide) (by agrind)
    have hm : i6.val * 2 ^ i7.val ≤ 3 * 2 ^ 24 := Nat.mul_le_mul (by agrind) hpw
    have hm4 : 4 ≤ i6.val * 2 ^ i7.val := by
      calc 4 = 2 * 2 := by norm_num
        _ ≤ i6.val * 2 ^ i7.val := Nat.mul_le_mul (by agrind) hpw1
    step as ⟨ i8, i8_post ⟩
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by scalar_tac)] at i8_post
    step as ⟨ offset, offset_post ⟩
    step as ⟨ i9, i9_post ⟩
    have hx24 : extra.val < 2 ^ 24 := by agrind
    have hi9 : i9.val * 2 ^ self.postfix.val < 2 ^ 29 := by
      have : i9.val < 2 ^ 26 := by agrind
      calc i9.val * 2 ^ self.postfix.val < 2 ^ 26 * 8 := Nat.mul_lt_mul_of_lt_of_le this hP8 (by decide)
        _ = 2 ^ 29 := by norm_num
    step as ⟨ i10, i10_post ⟩
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by scalar_tac)] at i10_post
    step as ⟨ i11, i11_post ⟩
    step as ⟨ i12, i12_post ⟩
    step as ⟨ i13, i13_post ⟩
    have hlowlt : low.val < 8 := by
      rw [hlow]; exact Nat.lt_of_lt_of_le (Nat.mod_lt _ (Nat.two_pow_pos _)) hP8
    have hi13 : i13.val = low.val + self.direct.val + 1 := by
      rw [i13_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]; agrind
    step as ⟨ r, r_post ⟩
    simp only [Mbrotli.Model.decode, hlt, ite_false]
    rw [r_post, i10_post, i9_post, offset_post, i8_post, hi6, i7_post, hi13, hlow, code_post, i1_post]
    simp only [Mbrotli.Model.width, hlt, ite_false]
    agrind

@[step]
theorem DistanceLayout.long_distance.spec (self : DistanceLayout) (symbol : Usize) (extra : U64)
    (hp : self.postfix.val ≤ 3) (hd : self.direct.val ≤ 120)
    (hs16 : 16 ≤ symbol.val) (hs : symbol.val < 16 + self.direct.val + 2 * 62 * 2 ^ self.postfix.val)
    (hx : extra.val < 2 ^ Mbrotli.Model.width self.postfix.val self.direct.val symbol.val) :
    self.long_distance symbol extra ⦃ (r : U128) =>
      r.val = Mbrotli.Model.decode self.postfix.val self.direct.val symbol.val extra.val ⦄ := by
  have := numBits_ge
  have hP8 : 2 ^ self.postfix.val ≤ 8 := by
    calc 2 ^ self.postfix.val ≤ 2 ^ 3 := Nat.pow_le_pow_right (by decide) hp
      _ = 8 := by norm_num
  have hP1 : 1 ≤ 2 ^ self.postfix.val := Nat.one_le_two_pow
  unfold DistanceLayout.long_distance
  step as ⟨ i, i_post ⟩
  split
  · /- A direct code: the distance is the symbol past the short codes. -/
    step as ⟨ i1, i1_post ⟩
    step as ⟨ i2, i2_post ⟩
    have hlt : symbol.val < 16 + self.direct.val := by scalar_tac
    rw [UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    simp only [Mbrotli.Model.decode, hlt, ite_true]
    agrind
  · have hlt : ¬ symbol.val < 16 + self.direct.val := by scalar_tac
    obtain ⟨hw, hw1⟩ := width_le self.postfix.val self.direct.val symbol.val 62 (by agrind) hs
    step as ⟨ i1, i1_post ⟩
    step as ⟨ code, code_post ⟩
    step as ⟨ high, high_post ⟩
    step as ⟨ i2, i2_post ⟩
    rw [Nat.one_shiftLeft, Nat.mod_eq_of_lt (two_pow_lt_usize _ (by agrind))] at i2_post
    step as ⟨ i3, i3_post ⟩
    step as ⟨ low, low_post ⟩
    step as ⟨ i4, i4_post ⟩
    step as ⟨ i5, i5_post ⟩
    step as ⟨ i6, i6_post ⟩
    step as ⟨ i7, i7_post ⟩
    have hlow : low.val = code.val % 2 ^ self.postfix.val := by
      rw [low_post, UScalar.val_and, i3_post, i2_post, Nat.and_two_pow_sub_one_eq_mod]
    have hi4 : i4.val = code.val / 2 ^ self.postfix.val % 2 := by
      rw [i4_post, UScalar.val_and, high_post, Nat.shiftRight_eq_div_pow]
      simp [Nat.and_one_is_mod]
    have hi6 : i6.val = 2 + code.val / 2 ^ self.postfix.val % 2 := by
      rw [i6_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]; agrind
    have hpw : 2 ^ i7.val ≤ 2 ^ 62 := Nat.pow_le_pow_right (by decide) (by agrind)
    have hpw1 : 2 ≤ 2 ^ i7.val := by
      calc 2 = 2 ^ 1 := by norm_num
        _ ≤ 2 ^ i7.val := Nat.pow_le_pow_right (by decide) (by agrind)
    have hm : i6.val * 2 ^ i7.val ≤ 3 * 2 ^ 62 := Nat.mul_le_mul (by agrind) hpw
    have hm4 : 4 ≤ i6.val * 2 ^ i7.val := by
      calc 4 = 2 * 2 := by norm_num
        _ ≤ i6.val * 2 ^ i7.val := Nat.mul_le_mul (by agrind) hpw1
    step as ⟨ i8, i8_post ⟩
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by scalar_tac)] at i8_post
    step as ⟨ offset, offset_post ⟩
    step as ⟨ i9, i9_post ⟩
    have hx62 : extra.val < 2 ^ 62 := by agrind
    have hi9 : i9.val = extra.val := by
      rw [i9_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    step as ⟨ i10, i10_post ⟩
    have hi10 : i10.val * 2 ^ self.postfix.val < 2 ^ 67 := by
      have : i10.val < 2 ^ 64 := by agrind
      calc i10.val * 2 ^ self.postfix.val < 2 ^ 64 * 8 := Nat.mul_lt_mul_of_lt_of_le this hP8 (by decide)
        _ = 2 ^ 67 := by norm_num
    step as ⟨ i11, i11_post ⟩
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by scalar_tac)] at i11_post
    have hlowlt : low.val < 8 := by
      rw [hlow]; exact Nat.lt_of_lt_of_le (Nat.mod_lt _ (Nat.two_pow_pos _)) hP8
    step as ⟨ i12, i12_post ⟩
    have hi12 : i12.val = low.val := by
      rw [i12_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    step as ⟨ i13, i13_post ⟩
    step as ⟨ i14, i14_post ⟩
    have hi14 : i14.val = self.direct.val := by
      rw [i14_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    step as ⟨ i15, i15_post ⟩
    step as ⟨ r, r_post ⟩
    simp only [Mbrotli.Model.decode, hlt, ite_false]
    rw [r_post, i15_post, hi14, i13_post, hi12, i11_post, i10_post, hi9, offset_post, i8_post, hi6,
      i7_post, hlow, code_post, i1_post]
    simp only [Mbrotli.Model.width, hlt, ite_false]
    agrind

/-- **Spec theorem for `mbrotli::decompressor::core::distance::DistanceLayout::from_header`**
The six header bits hold `NPOSTFIX` in the low two and `NDIRECT >> NPOSTFIX`
in the high four (RFC 7932, section 9.2). -/
@[step]
theorem DistanceLayout.from_header.spec (header : U8) (large : Bool) (h : header.val < 64) :
    DistanceLayout.from_header header large ⦃ (r : DistanceLayout) =>
      r.postfix.val = header.val % 4 ∧
      r.direct.val = header.val / 4 * 2 ^ (header.val % 4) ∧ r.large = large ⦄ := by
  have := numBits_ge
  unfold DistanceLayout.from_header
  step as ⟨ «postfix», postfix_post ⟩
  have hpost : «postfix».val = header.val % 4 := by
    rw [postfix_post, UScalar.val_and]
    exact Nat.and_two_pow_sub_one_eq_mod header.val 2
  step as ⟨ i, i_post ⟩
  step as ⟨ i1, i1_post ⟩
  have hi1 : i1.val = header.val / 4 := by
    rw [i1_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (lt_usize_pow _ (by agrind)), i_post,
      Nat.shiftRight_eq_div_pow]
  step as ⟨ i2, i2_post ⟩
  have h4 : 2 ^ (header.val % 4) ≤ 8 := (two_pow_postfix_le _ (by agrind)).2
  rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by have := usize_size_ge; rw [hi1, hpost]; agrind)] at i2_post
  exact ⟨hpost, by rw [i2_post, hi1, hpost]⟩

/-- **Spec theorem for `mbrotli::decompressor::core::distance::DistanceLayout::alphabet`**
`16 + NDIRECT + (48 << NPOSTFIX)` symbols, or `124 << NPOSTFIX` past the direct
codes in a large-window stream. -/
@[step]
theorem DistanceLayout.alphabet.spec (self : DistanceLayout)
    (hp : self.postfix.val ≤ 3) (hd : self.direct.val ≤ 120) :
    self.alphabet ⦃ (r : Usize) =>
      r.val = 16 + self.direct.val + 2 * (if self.large then 62 else 24) * 2 ^ self.postfix.val ⦄ := by
  obtain ⟨hP1, hP8⟩ := two_pow_postfix_le _ hp
  have := numBits_ge
  unfold DistanceLayout.alphabet
  step as ⟨ i, i_post ⟩
  cases hl : self.large
  · simp only [Bool.false_eq_true, ite_false]
    step as ⟨ i1, i1_post ⟩
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by have := usize_size_ge; agrind)] at i1_post
    step*
  · simp only [ite_true]
    step as ⟨ i1, i1_post ⟩
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by have := usize_size_ge; agrind)] at i1_post
    step*

end mbrotli
