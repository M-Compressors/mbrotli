import Mbrotli.DecoderDistance
import Mbrotli.EncoderDistance

/-! # Distance codes survive the trip from encoder to decoder

For every distance parameter header and every distance the encoder may emit
under it, the decoder's layout for that header accepts the encoder's symbol,
reads exactly the number of extra bits the encoder wrote, and rebuilds the
original distance. Both directions are the generated translations of the Rust
code; nothing here restates either of them.
-/

open Aeneas Aeneas.Std Result

namespace mbrotli
open decompressor.core.distance shared.command shared.distance

/-- What the encoder emits, as the decoder will read it. -/
theorem emitted_fields (p nd dc n : Nat) (hp : p ≤ 3) (hnd : nd ≤ 120) (hlo : 16 + nd ≤ dc)
    (hhi : Mbrotli.Model.dist p nd dc < 2 ^ (n + p + 2)) (hn : n ≤ 30) :
    let d := Mbrotli.Model.dist p nd dc
    let code := 1024 * Mbrotli.Model.nbits p d + Mbrotli.Model.symbol p nd d
    16 ≤ code % 1024 ∧ code % 1024 < 16 + nd + 2 * n * 2 ^ p ∧
    Mbrotli.Model.width p nd (code % 1024) = code / 1024 ∧
    Mbrotli.Model.extra p d < 2 ^ Mbrotli.Model.width p nd (code % 1024) ∧
    Mbrotli.Model.decode p nd (code % 1024) (Mbrotli.Model.extra p d) + 15 = dc := by
  intro d code
  have hdlo : 2 ^ (p + 2) ≤ d := by simp only [d, Mbrotli.Model.dist]; agrind
  obtain ⟨_, hsym⟩ := Mbrotli.Model.symbol_lt p nd d n hdlo hhi
  obtain ⟨hge, hw, hx, hdec⟩ := Mbrotli.Model.decode_symbol p nd d hdlo
  have hP8 : 2 ^ p ≤ 8 := (two_pow_postfix_le p hp).2
  have h1024 : Mbrotli.Model.symbol p nd d < 1024 := by
    have : 16 + nd + 2 * n * 2 ^ p ≤ 1024 := by
      have : 2 * n * 2 ^ p ≤ 480 := by
        calc 2 * n * 2 ^ p ≤ 2 * 30 * 8 := Nat.mul_le_mul (Nat.mul_le_mul_left _ hn) hP8
          _ = 480 := by norm_num
      agrind
    agrind
  have hmod : code % 1024 = Mbrotli.Model.symbol p nd d := by
    simp only [code]; rw [Nat.mul_add_mod, Nat.mod_eq_of_lt h1024]
  have hdiv : code / 1024 = Mbrotli.Model.nbits p d := by
    simp only [code]; rw [Nat.mul_add_div (by decide), Nat.div_eq_of_lt h1024]; agrind
  rw [hmod, hdiv]
  refine ⟨by agrind, hsym, hw, hx, ?_⟩
  have : d + nd + 1 = 2 ^ (p + 2) + dc - 15 := by simp only [d, Mbrotli.Model.dist]; agrind
  agrind

/-- **Distance codes round-trip in a standard-window stream.**
For a distance parameter header `header` (`NPOSTFIX` in its low two bits,
`NDIRECT >> NPOSTFIX` in the high four), the encoder's alphabet for those
parameters, and every distance code the encoder may emit with it, the decoder:
* accepts the symbol, which lies inside the alphabet the encoder declared;
* reads the number of extra bits the encoder packed into the code;
* rebuilds the distance, without panicking or overflowing anywhere. -/
theorem distance_round_trip (header : U8) (hh : header.val < 64)
    (postfix_bits num_direct : U32) (hp : postfix_bits.val = header.val % 4)
    (hnd : num_direct.val = header.val / 4 * 2 ^ (header.val % 4))
    (params : DistanceParams) (hparams : DistanceParams.new postfix_bits num_direct = ok params)
    (distance_code : Usize) (hlo : 16 + num_direct.val ≤ distance_code.val)
    (hhi : distance_code.val - 15 ≤ params.max_distance.val) :
    prefix_encode_copy_distance distance_code num_direct postfix_bits ⦃ (code : U16) (extra : U32) =>
      DistanceLayout.from_header header false ⦃ (layout : DistanceLayout) =>
        ∀ (symbol : Usize) (field : U64), symbol.val = code.val % 1024 → field.val = extra.val →
          layout.alphabet ⦃ (a : Usize) =>
            symbol.val < a.val ∧ a.val = params.alphabet_size_max.val ⦄ ∧
          layout.extra_bits symbol ⦃ (w : U32) => w.val = code.val / 1024 ⦄ ∧
          layout.short_window_distance symbol field ⦃ (d : U64) =>
            d.val + 15 = distance_code.val ⦄ ⦄ ⦄ := by
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
  obtain ⟨h16, hsym, hw, hx, hdec⟩ :=
    emitted_fields postfix_bits.val num_direct.val distance_code.val 24 hp3 hnd120 hlo hdlt (by decide)
  apply WP.spec_mono (prefix_encode_copy_distance.spec distance_code num_direct postfix_bits hp3 hnd120
    hlo hdc)
  rintro ⟨code, extra⟩ ⟨hcode, hextra⟩
  apply WP.spec_mono (DistanceLayout.from_header.spec header false hh)
  rintro layout ⟨hlp, hld, hll⟩
  intro symbol field hsymb hfield
  have hlp' : layout.postfix.val = postfix_bits.val := by rw [hlp, hp]
  have hld' : layout.direct.val = num_direct.val := by rw [hld, hnd]
  rw [hcode] at hsymb
  refine ⟨?_, ?_, ?_⟩
  · apply WP.spec_mono (DistanceLayout.alphabet.spec layout (by agrind) (by agrind))
    intro a ha
    rw [hll] at ha
    simp only [Bool.false_eq_true, ite_false] at ha
    rw [ha, halpha, hlp', hld', hsymb]
    exact ⟨hsym, rfl⟩
  · apply WP.spec_mono (DistanceLayout.extra_bits.spec layout symbol (by agrind) (by agrind)
      (by rw [hsymb]; agrind))
    intro w hw'
    rw [hw', hlp', hld', hsymb, hw, hcode]
  · apply WP.spec_mono (DistanceLayout.short_window_distance.spec layout symbol field (by agrind)
      (by agrind) (by rw [hsymb]; exact h16) (by rw [hlp', hld', hsymb]; exact hsym)
      (by rw [hlp', hld', hsymb, hfield, hextra]; exact hx))
    intro d hd
    rw [hd, hlp', hld', hsymb, hfield, hextra, hdec]

/-- **Distance codes round-trip in a large-window stream (RFC 9841).**
The same guarantee for every distance up to `MAX_ALLOWED_DISTANCE`, the limit
the encoder enforces, decoded through the widening `long_distance`. -/
theorem large_distance_round_trip (header : U8) (hh : header.val < 64)
    (postfix_bits num_direct : U32) (hp : postfix_bits.val = header.val % 4)
    (hnd : num_direct.val = header.val / 4 * 2 ^ (header.val % 4))
    (distance_code : Usize) (hlo : 16 + num_direct.val ≤ distance_code.val)
    (hhi : distance_code.val - 15 ≤ MAX_ALLOWED_DISTANCE.val) :
    prefix_encode_copy_distance distance_code num_direct postfix_bits ⦃ (code : U16) (extra : U32) =>
      DistanceLayout.from_header header true ⦃ (layout : DistanceLayout) =>
        ∀ (symbol : Usize) (field : U64), symbol.val = code.val % 1024 → field.val = extra.val →
          layout.alphabet ⦃ (a : Usize) => symbol.val < a.val ⦄ ∧
          layout.extra_bits symbol ⦃ (w : U32) => w.val = code.val / 1024 ⦄ ∧
          layout.long_distance symbol field ⦃ (d : U128) =>
            d.val + 15 = distance_code.val ⦄ ⦄ ⦄ := by
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
  obtain ⟨h16, hsym, hw, hx, hdec⟩ :=
    emitted_fields postfix_bits.val num_direct.val distance_code.val 30 hp3 hnd120 hlo hdlt le_rfl
  have hP1 : 1 ≤ 2 ^ postfix_bits.val := Nat.one_le_two_pow
  have hsym62 : 16 + num_direct.val + 2 * 30 * 2 ^ postfix_bits.val ≤
      16 + num_direct.val + 2 * 62 * 2 ^ postfix_bits.val := by agrind
  apply WP.spec_mono (prefix_encode_copy_distance.spec distance_code num_direct postfix_bits hp3 hnd120
    hlo hdc)
  rintro ⟨code, extra⟩ ⟨hcode, hextra⟩
  apply WP.spec_mono (DistanceLayout.from_header.spec header true hh)
  rintro layout ⟨hlp, hld, hll⟩
  intro symbol field hsymb hfield
  have hlp' : layout.postfix.val = postfix_bits.val := by rw [hlp, hp]
  have hld' : layout.direct.val = num_direct.val := by rw [hld, hnd]
  rw [hcode] at hsymb
  refine ⟨?_, ?_, ?_⟩
  · apply WP.spec_mono (DistanceLayout.alphabet.spec layout (by agrind) (by agrind))
    intro a ha
    rw [hll] at ha
    simp only [ite_true] at ha
    rw [ha, hlp', hld', hsymb]
    agrind
  · apply WP.spec_mono (DistanceLayout.extra_bits.spec layout symbol (by agrind) (by agrind)
      (by rw [hsymb]; agrind))
    intro w hw'
    rw [hw', hlp', hld', hsymb, hw, hcode]
  · apply WP.spec_mono (DistanceLayout.long_distance.spec layout symbol field (by agrind)
      (by agrind) (by rw [hsymb]; exact h16) (by rw [hlp', hld', hsymb]; agrind)
      (by rw [hlp', hld', hsymb, hfield, hextra]; exact hx))
    intro d hd
    rw [hd, hlp', hld', hsymb, hfield, hextra, hdec]

end mbrotli
