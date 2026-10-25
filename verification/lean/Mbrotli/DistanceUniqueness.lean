import Mbrotli.DistanceRoundTrip

/-! # Explicit distance codes are unique

The round trip shows that the decoder reads back what the encoder writes. This
file shows the converse: no other explicit code means the same distance. For a
given header, the pair of a symbol past the sixteen short codes and an extra
field of the width that symbol reads, which the decoder resolves to a distance,
is exactly the pair the encoder emits for it. Any encoder that writes an
explicit code, Google's C library included, therefore writes this pair; it may
still choose one of the short codes, which refer to the distance cache and are
outside this statement.
-/

open Aeneas Aeneas.Std Result

namespace mbrotli
open decompressor.core.distance shared.command shared.distance

/-- **Explicit distance codes are unique in a standard-window stream.**
Under the hypotheses of `distance_round_trip`, every explicit symbol inside the
encoder's alphabet, with an extra field of the width `extra_bits` gives it, that
`short_window_distance` resolves to the distance is the encoder's own pair. -/
theorem distance_code_unique (header : U8) (hh : header.val < 64)
    (postfix_bits num_direct : U32) (hp : postfix_bits.val = header.val % 4)
    (hnd : num_direct.val = header.val / 4 * 2 ^ (header.val % 4))
    (params : DistanceParams) (hparams : DistanceParams.new postfix_bits num_direct = ok params)
    (distance_code : Usize) (hlo : 16 + num_direct.val ≤ distance_code.val)
    (hhi : distance_code.val - 15 ≤ params.max_distance.val) :
    prefix_encode_copy_distance distance_code num_direct postfix_bits ⦃ (code : U16) (extra : U32) =>
      DistanceLayout.from_header header false ⦃ (layout : DistanceLayout) =>
        ∀ (symbol : Usize) (field : U64), 16 ≤ symbol.val →
          symbol.val < params.alphabet_size_max.val →
          layout.extra_bits symbol ⦃ (w : U32) => field.val < 2 ^ w.val →
            layout.short_window_distance symbol field ⦃ (d : U64) =>
              d.val + 15 = distance_code.val →
                symbol.val = code.val % 1024 ∧ field.val = extra.val ⦄ ⦄ ⦄ ⦄ := by
  have hp3 : postfix_bits.val ≤ 3 := by agrind
  have hP8 : 2 ^ (header.val % 4) ≤ 8 := (two_pow_postfix_le _ (by agrind)).2
  have hnd120 : num_direct.val ≤ 120 := by
    rw [hnd]
    calc header.val / 4 * 2 ^ (header.val % 4) ≤ 15 * 8 := Nat.mul_le_mul (by agrind) hP8
      _ = 120 := by norm_num
  have hpar := DistanceParams.new.spec postfix_bits num_direct hp3 hnd120
  rw [hparams, WP.spec_ok] at hpar
  obtain ⟨-, -, halpha, -, hmax⟩ := hpar
  have hP29 : 2 ^ (24 + postfix_bits.val + 2) ≤ 2 ^ 29 := Nat.pow_le_pow_right (by decide) (by agrind)
  have hdlt : Mbrotli.Model.dist postfix_bits.val num_direct.val distance_code.val <
      2 ^ (24 + postfix_bits.val + 2) := by
    simp only [Mbrotli.Model.dist]; agrind
  have hdc : distance_code.val ≤ 2 ^ 31 + 15 := by agrind
  obtain ⟨h16, -, -, hx, hdec⟩ :=
    emitted_fields postfix_bits.val num_direct.val distance_code.val 24 hp3 hnd120 hlo hdlt (by decide)
  have hP8' : 2 ^ postfix_bits.val ≤ 8 := (two_pow_postfix_le _ hp3).2
  apply WP.spec_mono (prefix_encode_copy_distance.spec distance_code num_direct postfix_bits hp3 hnd120
    hlo hdc)
  rintro ⟨code, extra⟩ ⟨hcode, hextra⟩
  apply WP.spec_mono (DistanceLayout.from_header.spec header false hh)
  rintro layout ⟨hlp, hld, -⟩
  intro symbol field hs16 hsa
  have hlp' : layout.postfix.val = postfix_bits.val := by rw [hlp, hp]
  have hld' : layout.direct.val = num_direct.val := by rw [hld, hnd]
  rw [halpha] at hsa
  apply WP.spec_mono (DistanceLayout.extra_bits.spec layout symbol (by agrind) (by agrind) (by agrind))
  intro w hw hfield
  rw [hw, hlp', hld'] at hfield
  apply WP.spec_mono (DistanceLayout.short_window_distance.spec layout symbol field (by agrind)
    (by agrind) hs16 (by rw [hlp', hld']; exact hsa) (by rw [hlp', hld']; exact hfield))
  intro d hd hdist
  rw [hlp', hld'] at hd
  rw [hcode, hextra]
  exact Mbrotli.Model.decode_injective _ _ _ _ _ _ hs16 h16 hfield hx (by agrind)

/-- **Explicit distance codes are unique in a large-window stream (RFC 9841).**
The same for every distance up to `MAX_ALLOWED_DISTANCE`, every explicit symbol
of the 124-bucket alphabet and `long_distance`. -/
theorem large_distance_code_unique (header : U8) (hh : header.val < 64)
    (postfix_bits num_direct : U32) (hp : postfix_bits.val = header.val % 4)
    (hnd : num_direct.val = header.val / 4 * 2 ^ (header.val % 4))
    (distance_code : Usize) (hlo : 16 + num_direct.val ≤ distance_code.val)
    (hhi : distance_code.val - 15 ≤ MAX_ALLOWED_DISTANCE.val) :
    prefix_encode_copy_distance distance_code num_direct postfix_bits ⦃ (code : U16) (extra : U32) =>
      DistanceLayout.from_header header true ⦃ (layout : DistanceLayout) =>
        ∀ (symbol : Usize) (field : U64), 16 ≤ symbol.val →
          symbol.val < 16 + num_direct.val + 2 * 62 * 2 ^ postfix_bits.val →
          layout.extra_bits symbol ⦃ (w : U32) => field.val < 2 ^ w.val →
            layout.long_distance symbol field ⦃ (d : U128) =>
              d.val + 15 = distance_code.val →
                symbol.val = code.val % 1024 ∧ field.val = extra.val ⦄ ⦄ ⦄ ⦄ := by
  have hp3 : postfix_bits.val ≤ 3 := by agrind
  have hP8 : 2 ^ (header.val % 4) ≤ 8 := (two_pow_postfix_le _ (by agrind)).2
  have hnd120 : num_direct.val ≤ 120 := by
    rw [hnd]
    calc header.val / 4 * 2 ^ (header.val % 4) ≤ 15 * 8 := Nat.mul_le_mul (by agrind) hP8
      _ = 120 := by norm_num
  have hP32 : 2 ^ 32 ≤ 2 ^ (30 + postfix_bits.val + 2) := Nat.pow_le_pow_right (by decide) (by agrind)
  have hP5 : 2 ^ (postfix_bits.val + 2) ≤ 2 ^ 5 := Nat.pow_le_pow_right (by decide) (by agrind)
  have hdlt : Mbrotli.Model.dist postfix_bits.val num_direct.val distance_code.val <
      2 ^ (30 + postfix_bits.val + 2) := by
    simp only [Mbrotli.Model.dist]; agrind
  have hdc : distance_code.val ≤ 2 ^ 31 + 15 := by agrind
  obtain ⟨h16, -, -, hx, hdec⟩ :=
    emitted_fields postfix_bits.val num_direct.val distance_code.val 30 hp3 hnd120 hlo hdlt le_rfl
  have hP8' : 2 ^ postfix_bits.val ≤ 8 := (two_pow_postfix_le _ hp3).2
  apply WP.spec_mono (prefix_encode_copy_distance.spec distance_code num_direct postfix_bits hp3 hnd120
    hlo hdc)
  rintro ⟨code, extra⟩ ⟨hcode, hextra⟩
  apply WP.spec_mono (DistanceLayout.from_header.spec header true hh)
  rintro layout ⟨hlp, hld, -⟩
  intro symbol field hs16 hsa
  have hlp' : layout.postfix.val = postfix_bits.val := by rw [hlp, hp]
  have hld' : layout.direct.val = num_direct.val := by rw [hld, hnd]
  apply WP.spec_mono (DistanceLayout.extra_bits.spec layout symbol (by agrind) (by agrind) (by agrind))
  intro w hw hfield
  rw [hw, hlp', hld'] at hfield
  apply WP.spec_mono (DistanceLayout.long_distance.spec layout symbol field (by agrind)
    (by agrind) hs16 (by rw [hlp', hld']; exact hsa) (by rw [hlp', hld']; exact hfield))
  intro d hd hdist
  rw [hlp', hld'] at hd
  rw [hcode, hextra]
  exact Mbrotli.Model.decode_injective _ _ _ _ _ _ hs16 h16 hfield hx (by agrind)

end mbrotli
