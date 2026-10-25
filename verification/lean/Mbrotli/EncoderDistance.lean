import Mbrotli.Basic
import Mbrotli.Model

/-! # The encoder's distance prefix codes

Specification of `mbrotli::shared::command::prefix_encode_copy_distance`: for
every distance code past the short and direct codes, the function neither panics
nor overflows, and it returns the symbol and extra field of `Mbrotli.Model`.
-/

open Aeneas Aeneas.Std Result

namespace mbrotli
open shared.command shared.distance

/- Shifts and masks by a variable amount, restated as the arithmetic they
   perform, so that `step` can discharge the overflow side conditions. -/
attribute [local simp, local scalar_tac_simps] Nat.one_shiftLeft Nat.shiftLeft_eq
  Nat.shiftRight_eq_div_pow Nat.and_two_pow_sub_one_eq_mod Nat.and_one_is_mod

@[step]
theorem shared.command.prefix_encode_copy_distance.spec (distance_code : Usize)
    (num_direct_codes postfix_bits : U32)
    (hp : postfix_bits.val ≤ 3) (hnd : num_direct_codes.val ≤ 120)
    (hlo : 16 + num_direct_codes.val ≤ distance_code.val)
    (hhi : distance_code.val ≤ 2 ^ 31 + 15) :
    prefix_encode_copy_distance distance_code num_direct_codes postfix_bits
      ⦃ (code : U16) (extra : U32) =>
        let d := Mbrotli.Model.dist postfix_bits.val num_direct_codes.val distance_code.val
        code.val = 1024 * Mbrotli.Model.nbits postfix_bits.val d +
          Mbrotli.Model.symbol postfix_bits.val num_direct_codes.val d ∧
        extra.val = Mbrotli.Model.extra postfix_bits.val d ⦄ := by
  have := numBits_ge
  have hP8 : 2 ^ postfix_bits.val ≤ 8 := by
    calc 2 ^ postfix_bits.val ≤ 2 ^ 3 := Nat.pow_le_pow_right (by decide) hp
      _ = 8 := by norm_num
  have hP1 : 1 ≤ 2 ^ postfix_bits.val := Nat.one_le_two_pow
  unfold prefix_encode_copy_distance
  step as ⟨ i, i_post ⟩
  step as ⟨ i1, i1_post ⟩
  have hi1 : i1.val = 16 + num_direct_codes.val := by
    rw [i1_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]; agrind
  split
  · scalar_tac
  · step as ⟨ i2, i2_post ⟩
    step as ⟨ i3, i3_post ⟩
    rw [Nat.one_shiftLeft, Nat.mod_eq_of_lt (two_pow_lt_usize _ (by agrind))] at i3_post
    step as ⟨ i4, i4_post ⟩
    have hi4 : i4.val = 16 := by
      rw [i4_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]; agrind
    step as ⟨ i5, i5_post ⟩
    step as ⟨ i6, i6_post ⟩
    have hi6 : i6.val = num_direct_codes.val := by
      rw [i6_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    step as ⟨ i7, i7_post ⟩
    have hP32 : 2 ^ (postfix_bits.val + 2) ≤ 32 := by
      calc 2 ^ (postfix_bits.val + 2) ≤ 2 ^ 5 := Nat.pow_le_pow_right (by decide) (by agrind)
        _ = 32 := by norm_num
    step as ⟨ dist, dist_post ⟩
    set D := Mbrotli.Model.dist postfix_bits.val num_direct_codes.val distance_code.val with hD
    have hdist : dist.val = D := by
      rw [dist_post, i3_post, i7_post, i5_post, hi4, hi6, hD, i2_post, Mbrotli.Model.dist]
    have hDlo : 2 ^ (postfix_bits.val + 2) ≤ D := by rw [hD, Mbrotli.Model.dist]; agrind
    have hDhi : D < 2 ^ (30 + postfix_bits.val + 2) := by
      have : 2 ^ 32 ≤ 2 ^ (30 + postfix_bits.val + 2) := Nat.pow_le_pow_right (by decide) (by agrind)
      rw [hD, Mbrotli.Model.dist]; agrind
    obtain ⟨hn1, hpre, hex, hpost, hlog, hsplit⟩ := Mbrotli.Model.decompose _ _ hDlo
    obtain ⟨hn30, hsym⟩ := Mbrotli.Model.symbol_lt postfix_bits.val num_direct_codes.val D 30 hDlo hDhi
    step as ⟨ i8, i8_post ⟩
    rw [hdist, hlog] at i8_post
    have hD32 : D < 2 ^ 32 := by rw [hD, Mbrotli.Model.dist]; agrind
    have hlog32 : Nat.log 2 D < 32 := Nat.log_lt_of_lt_pow (by agrind) hD32
    have hn32 : Mbrotli.Model.nbits postfix_bits.val D + postfix_bits.val ≤ 30 := by agrind
    step as ⟨ bucket, bucket_post ⟩
    step as ⟨ i9, i9_post ⟩
    rw [Nat.one_shiftLeft, Nat.mod_eq_of_lt (two_pow_lt_usize _ (by agrind))] at i9_post
    step as ⟨ postfix_mask, postfix_mask_post ⟩
    step as ⟨ «postfix», postfix_post ⟩
    have hpostfix : «postfix».val = Mbrotli.Model.postfixBits postfix_bits.val D := by
      rw [postfix_post, UScalar.val_and, postfix_mask_post, i9_post, Nat.and_two_pow_sub_one_eq_mod,
        hdist, Mbrotli.Model.postfixBits]
    step as ⟨ i10, i10_post ⟩
    step as ⟨ «prefix», prefix_post ⟩
    have hprefix : «prefix».val = Mbrotli.Model.prefixBit D := by
      rw [prefix_post, UScalar.val_and, i10_post, Nat.shiftRight_eq_div_pow, hdist, bucket_post,
        Mbrotli.Model.prefixBit, hlog, i8_post]
      simp [Nat.and_one_is_mod]
    step as ⟨ i11, i11_post ⟩
    have hbucket : bucket.val = Mbrotli.Model.nbits postfix_bits.val D + postfix_bits.val := by agrind
    have hoff : (2 + Mbrotli.Model.prefixBit D) * 2 ^ bucket.val ≤ D := by rw [hbucket]; agrind
    step as ⟨ offset, offset_post ⟩
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by have := usize_size_ge; agrind)] at offset_post
    step as ⟨ nbits, nbits_post ⟩
    step as ⟨ i12, i12_post ⟩
    have hi12 : i12.val = Mbrotli.Model.nbits postfix_bits.val D := by
      rw [i12_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (lt_usize_pow _ (by agrind))]; agrind
    step as ⟨ i13, i13_post ⟩
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by have := usize_size_ge; agrind)] at i13_post
    step as ⟨ i14, i14_post ⟩
    have hi14 : i14.val = 16 := by
      rw [i14_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (lt_usize_pow _ (by agrind))]; agrind
    step as ⟨ i15, i15_post ⟩
    have hi15 : i15.val = num_direct_codes.val := by
      rw [i15_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (lt_usize_pow _ (by agrind))]
    step as ⟨ i16, i16_post ⟩
    step as ⟨ i17, i17_post ⟩
    have hi17 : i17.val = Mbrotli.Model.nbits postfix_bits.val D := by
      rw [i17_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (lt_usize_pow _ (by agrind))]; agrind
    step as ⟨ i18, i18_post ⟩
    step as ⟨ i19, i19_post ⟩
    step as ⟨ i20, i20_post ⟩
    have hi20 : i20.val * 2 ^ postfix_bits.val < 2 ^ 10 := by
      have : i20.val < 62 := by agrind
      calc i20.val * 2 ^ postfix_bits.val < 62 * 8 := Nat.mul_lt_mul_of_lt_of_le this hP8 (by decide)
        _ ≤ 2 ^ 10 := by norm_num
    step as ⟨ i21, i21_post ⟩
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by have := usize_size_ge; agrind)] at i21_post
    step as ⟨ i22, i22_post ⟩
    step as ⟨ i23, i23_post ⟩
    have hsym : i23.val = Mbrotli.Model.symbol postfix_bits.val num_direct_codes.val D := by
      rw [i23_post, i22_post, i21_post, i20_post, i19_post, i18_post, hi17, i16_post, hi14, hi15, hpostfix, hprefix,
        Mbrotli.Model.symbol]
    have hsym1024 : i23.val < 2 ^ 10 := by
      rw [hsym]; have : 16 + num_direct_codes.val + 2 * 30 * 2 ^ postfix_bits.val ≤ 1024 := by agrind
      agrind
    step as ⟨ code, code_post ⟩
    have hcode : code.val = 1024 * Mbrotli.Model.nbits postfix_bits.val D +
        Mbrotli.Model.symbol postfix_bits.val num_direct_codes.val D := by
      rw [code_post, UScalar.val_or, i13_post, ← Nat.shiftLeft_eq,
        ← Nat.shiftLeft_add_eq_or_of_lt hsym1024, Nat.shiftLeft_eq, hi12, hsym]
      agrind
    step as ⟨ i24, i24_post ⟩
    step as ⟨ i25, i25_post ⟩
    step as ⟨ i26, i26_post ⟩
    step as ⟨ extra, extra_post ⟩
    have hbl : bucket.val = Nat.log 2 D - 1 := by agrind
    refine ⟨?_, ?_⟩
    · rw [i24_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by rw [hcode]; agrind), hcode]
    · rw [extra_post, UScalar.cast_val_eq, i26_post, Nat.shiftRight_eq_div_pow, i25_post, hdist,
        offset_post, i11_post, hprefix, hbl, Mbrotli.Model.extra]
      have : (D - (2 + Mbrotli.Model.prefixBit D) * 2 ^ (Nat.log 2 D - 1)) / 2 ^ postfix_bits.val
          < 2 ^ 32 := by
        have := Nat.div_le_self (D - (2 + Mbrotli.Model.prefixBit D) * 2 ^ (Nat.log 2 D - 1))
          (2 ^ postfix_bits.val)
        agrind
      exact Nat.mod_eq_of_lt this

/-- **Spec theorem for `mbrotli::shared::distance::DistanceParams::new`**
The RFC 7932 alphabet the encoder writes for `postfix_bits` and `num_direct`:
`16 + NDIRECT + (48 << NPOSTFIX)` symbols reaching distances up to
`NDIRECT + 2 ^ (26 + NPOSTFIX) - 2 ^ (NPOSTFIX + 2)`. -/
@[step]
theorem shared.distance.DistanceParams.new.spec (postfix_bits num_direct : U32)
    (hp : postfix_bits.val ≤ 3) (hnd : num_direct.val ≤ 120) :
    DistanceParams.new postfix_bits num_direct ⦃ (r : DistanceParams) =>
      r.postfix_bits = postfix_bits ∧ r.num_direct = num_direct ∧
      r.alphabet_size_max.val = 16 + num_direct.val + 2 * 24 * 2 ^ postfix_bits.val ∧
      r.alphabet_size_limit = r.alphabet_size_max ∧
      r.max_distance.val + 2 ^ (postfix_bits.val + 2) =
        num_direct.val + 2 ^ (24 + postfix_bits.val + 2) ⦄ := by
  obtain ⟨hP1, hP8⟩ := two_pow_postfix_le _ hp
  have h26 : 2 ^ (24 + postfix_bits.val + 2) ≤ 2 ^ 29 := Nat.pow_le_pow_right (by decide) (by agrind)
  have h26' : 2 ^ 26 ≤ 2 ^ (24 + postfix_bits.val + 2) := Nat.pow_le_pow_right (by decide) (by agrind)
  have h2 : 2 ^ (postfix_bits.val + 2) ≤ 2 ^ 5 := Nat.pow_le_pow_right (by decide) (by agrind)
  unfold DistanceParams.new
  step*
  have hu : U32.size = 2 ^ 32 := by simp [U32.size, U32.numBits]
  have hpow1 : 2 ^ (postfix_bits.val + 1) = 2 * 2 ^ postfix_bits.val := by rw [Nat.pow_succ]; ring
  rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by rw [hu, i1_post, hpow1, MAX_DISTANCE_BITS_val]; agrind)] at i2_post
  rw [Nat.one_shiftLeft, Nat.mod_eq_of_lt (by rw [hu, i4_post, i3_post]; agrind)] at i5_post
  rw [Nat.one_shiftLeft, Nat.mod_eq_of_lt (by rw [hu, i7_post]; agrind)] at i8_post
  refine ⟨?_, ?_⟩
  · rw [alphabet_size_max_post, i_post, i2_post, i1_post, hpow1, MAX_DISTANCE_BITS_val]; agrind
  · rw [max_distance_post, i6_post, i5_post, i4_post, i3_post, i8_post, i7_post, MAX_DISTANCE_BITS_val]
    agrind

/-- **Spec theorem for `mbrotli::shared::command::prefix_encode_copy_distance`**,
short and direct codes: a distance code below `16 + NDIRECT` is its own symbol,
with no extra bits. -/
theorem shared.command.prefix_encode_copy_distance.spec_direct (distance_code : Usize)
    (num_direct_codes postfix_bits : U32) (hnd : num_direct_codes.val ≤ 120)
    (hlt : distance_code.val < 16 + num_direct_codes.val) :
    prefix_encode_copy_distance distance_code num_direct_codes postfix_bits
      ⦃ (code : U16) (extra : U32) => code.val = distance_code.val ∧ extra.val = 0 ⦄ := by
  have := numBits_ge
  unfold prefix_encode_copy_distance
  step as ⟨ i, i_post ⟩
  step as ⟨ i1, i1_post ⟩
  have hi1 : i1.val = 16 + num_direct_codes.val := by
    rw [i1_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (lt_usize_pow _ (by scalar_tac))]; agrind
  split
  · step as ⟨ i2, i2_post ⟩
    refine ⟨?_, rfl⟩
    rw [i2_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
  · scalar_tac

end mbrotli
