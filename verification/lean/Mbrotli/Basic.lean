import Mbrotli.Code.Funs

/-! # Facts shared by the proofs about the generated code

Platform bounds that hold on every target this crate supports (a `usize` of 32
or 64 bits), the value of the constants the specifications rely on, and the
specification of `shared::fast_log::log2_floor_non_zero`.
-/

open Aeneas Aeneas.Std Result

namespace mbrotli

/-- `usize` has at least 32 bits on every platform the crate builds for. -/
theorem numBits_ge : 32 ≤ System.Platform.numBits := by
  cases System.Platform.numBits_eq with
  | inl h => simp [h]
  | inr h => simp [h]

/-- `usize` has at most 64 bits. -/
theorem numBits_le : System.Platform.numBits ≤ 64 := by
  cases System.Platform.numBits_eq with
  | inl h => simp [h]
  | inr h => simp [h]

theorem usize_size_ge : 2 ^ 32 ≤ Usize.size := by
  rw [Usize.size_def, Usize.numBits_def]
  cases System.Platform.numBits_eq with
  | inl h => simp [h]
  | inr h => simp [h]

/-- Powers of two up to `2 ^ 31` survive the wrap of a `usize` shift. -/
theorem two_pow_lt_usize (p : Nat) (hp : p ≤ 31) : 2 ^ p < Usize.size := by
  have h : 2 ^ p < 2 ^ 32 := Nat.pow_lt_pow_right (by decide) (by agrind)
  have := usize_size_ge
  agrind

/-- A value below `2 ^ 32` survives a cast to `usize`. -/
theorem lt_usize_pow (x : Nat) (h : x < 2 ^ 32) : x < 2 ^ UScalarTy.Usize.numBits := by
  have : 2 ^ 32 ≤ 2 ^ UScalarTy.Usize.numBits := by
    rw [UScalarTy.Usize_numBits_eq]; exact Nat.pow_le_pow_right (by decide) numBits_ge
  agrind

/-- `2 ^ p` for a postfix width `p ≤ 3`. -/
theorem two_pow_postfix_le (p : Nat) (hp : p ≤ 3) : 1 ≤ 2 ^ p ∧ 2 ^ p ≤ 8 :=
  ⟨Nat.one_le_two_pow, by
    calc 2 ^ p ≤ 2 ^ 3 := Nat.pow_le_pow_right (by decide) hp
      _ = 8 := by norm_num⟩

@[simp, scalar_tac_simps, agrind =, grind =, bvify]
theorem decompressor.core.distance.SHORT_CODES_val :
    decompressor.core.distance.SHORT_CODES.val = 16 := by
  simp [decompressor.core.distance.SHORT_CODES]

@[simp, scalar_tac_simps, agrind =, grind =, bvify]
theorem shared.distance.NUM_DISTANCE_SHORT_CODES_val :
    shared.distance.NUM_DISTANCE_SHORT_CODES.val = 16 := by
  simp [shared.distance.NUM_DISTANCE_SHORT_CODES]

@[simp, scalar_tac_simps, agrind =, grind =, bvify]
theorem shared.distance.MAX_DISTANCE_BITS_val : shared.distance.MAX_DISTANCE_BITS.val = 24 := by
  simp [shared.distance.MAX_DISTANCE_BITS]

@[simp, scalar_tac_simps, agrind =, grind =, bvify]
theorem shared.distance.MAX_ALLOWED_DISTANCE_val :
    shared.distance.MAX_ALLOWED_DISTANCE.val = 2 ^ 31 - 4 := by
  simp [shared.distance.MAX_ALLOWED_DISTANCE]

theorem usize_log_lt (value : Usize) : Nat.log 2 value.val < UScalarTy.Usize.numBits := by
  have hb : value.val < 2 ^ UScalarTy.Usize.numBits := by simpa [UScalar.size] using value.hBounds
  have := numBits_ge
  by_cases hz : value.val = 0
  · simp only [hz, Nat.log_zero_right, UScalarTy.Usize_numBits_eq]; agrind
  · exact Nat.log_lt_of_lt_pow hz hb

theorem leading_zeros_val (value : Usize) (h : value.val ≠ 0) :
    (core.num.Usize.leading_zeros value).val =
      UScalarTy.Usize.numBits - Nat.log 2 value.val - 1 := by
  simp only [core.num.Usize.leading_zeros, BitVec.leadingZeros]
  have hne : ¬ (value.bv = 0#System.Platform.numBits) := by
    intro hz; apply h; simpa using congrArg BitVec.toNat hz
  have := numBits_le
  split
  · exact absurd ‹_› hne
  · simp
    change (BitVec.ofNat 32 _).toNat = _
    rw [BitVec.toNat_ofNat, Nat.mod_eq_of_lt]
    have : System.Platform.numBits - Nat.log 2 ↑value - 1 < 2 ^ 32 := by agrind
    exact this

/-- **Spec theorem for `mbrotli::shared::fast_log::log2_floor_non_zero`**
The floor of the base-2 logarithm of a non-zero `usize`. -/
@[step]
theorem shared.fast_log.log2_floor_non_zero.spec (value : Usize) (h : value.val ≠ 0) :
    shared.fast_log.log2_floor_non_zero value ⦃ (r : U32) =>
      r.val = Nat.log 2 value.val ⦄ := by
  have hl := usize_log_lt value
  have hz := leading_zeros_val value h
  unfold shared.fast_log.log2_floor_non_zero
  step*

end mbrotli
