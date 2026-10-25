module

public import Mathlib.Data.Nat.Log
public import Mathlib.Tactic.Ring

/-! # Distance codes of RFC 7932, section 4, over natural numbers

The encoder splits a distance into a prefix symbol and an extra-bit field; the
decoder rebuilds the distance from both. These definitions restate the two
directions with unbounded arithmetic, so the proofs about the generated code
only have to show that the Rust functions compute them without overflowing.
-/

@[expose] public section

namespace Mbrotli.Model

/-- The value the encoder splits: the distance code past the short and direct
codes, offset by `4 << p` so that its highest bit selects the bucket. -/
def dist (p nd dc : Nat) : Nat := 2 ^ (p + 2) + (dc - 16 - nd)

/-- The bit below the leading one of `d`, which picks one half of the bucket. -/
def prefixBit (d : Nat) : Nat := d / 2 ^ (Nat.log 2 d - 1) % 2

/-- Number of extra bits of `d`. -/
def nbits (p d : Nat) : Nat := Nat.log 2 d - 1 - p

/-- The low `p` bits of `d`, carried in the symbol. -/
def postfixBits (p d : Nat) : Nat := d % 2 ^ p

/-- The extra-bit field: what remains of `d` below the bucket offset. -/
def extra (p d : Nat) : Nat := (d - (2 + prefixBit d) * 2 ^ (Nat.log 2 d - 1)) / 2 ^ p

/-- The distance symbol the encoder emits for `d`. -/
def symbol (p nd d : Nat) : Nat :=
  16 + nd + (2 * (nbits p d - 1) + prefixBit d) * 2 ^ p + postfixBits p d

/-- The distance the decoder reads from symbol `sym` and extra field `ex` for a
symbol past the short codes (RFC 7932, section 4). -/
def decode (p nd sym ex : Nat) : Nat :=
  if sym < 16 + nd then sym - 15
  else
    let code := sym - 16 - nd
    let width := 1 + code / 2 ^ (p + 1)
    ((2 + code / 2 ^ p % 2) * 2 ^ width - 4 + ex) * 2 ^ p + code % 2 ^ p + nd + 1

/-- Number of extra bits the decoder reads after a symbol past the short codes. -/
def width (p nd sym : Nat) : Nat :=
  if sym < 16 + nd then 0 else 1 + (sym - 16 - nd) / 2 ^ (p + 1)

/-- The split every distance `d ≥ 4 << p` has: a bucket of width `n`, one bit
choosing its half, an extra field of `n` bits and `p` postfix bits. -/
theorem decompose (p d : Nat) (hd : 2 ^ (p + 2) ≤ d) :
    1 ≤ nbits p d ∧ prefixBit d < 2 ∧ extra p d < 2 ^ nbits p d ∧ postfixBits p d < 2 ^ p ∧
    Nat.log 2 d = nbits p d + p + 1 ∧
    d = (2 + prefixBit d) * 2 ^ (nbits p d + p) + extra p d * 2 ^ p + postfixBits p d := by
  have hlog : p + 2 ≤ Nat.log 2 d := Nat.le_log_of_pow_le (by decide) hd
  have hd0 : d ≠ 0 := by
    have : 0 < 2 ^ (p + 2) := Nat.two_pow_pos _
    grind
  obtain ⟨n, hn⟩ : ∃ n, Nat.log 2 d = n + 1 + p + 1 := ⟨Nat.log 2 d - p - 2, by grind⟩
  have hnb : nbits p d = n + 1 := by simp only [nbits, hn]; grind
  have hb : Nat.log 2 d - 1 = (n + 1) + p := by grind
  have hlo : 2 ^ Nat.log 2 d ≤ d := Nat.pow_log_le_self 2 hd0
  have hhi : d < 2 ^ (Nat.log 2 d).succ := Nat.lt_pow_succ_log_self (by decide) d
  set B := 2 ^ ((n + 1) + p) with hB
  have hBpos : 0 < B := Nat.two_pow_pos _
  have h2B : 2 ^ Nat.log 2 d = 2 * B := by rw [hn, hB]; ring
  have h4B : 2 ^ (Nat.log 2 d).succ = 4 * B := by rw [hn, hB, Nat.succ_eq_add_one]; ring
  have hq2 : 2 ≤ d / B := (Nat.le_div_iff_mul_le hBpos).2 (by grind)
  have hq4 : d / B < 4 := (Nat.div_lt_iff_lt_mul hBpos).2 (by grind)
  have hpre : prefixBit d = d / B - 2 := by
    simp only [prefixBit, hb, ← hB]; grind
  have hsplit : d = d / B * B + d % B := (Nat.div_add_mod' d B).symm
  have hP : 0 < 2 ^ p := Nat.two_pow_pos _
  have hBP : B = 2 ^ (n + 1) * 2 ^ p := by rw [hB, Nat.pow_add]
  have hex : extra p d = d % B / 2 ^ p := by
    simp only [extra, hb, ← hB, hpre]
    congr 1
    grind
  have hrmod : d % B % 2 ^ p = d % 2 ^ p := by
    rw [hBP, Nat.mod_mul_left_mod]
  refine ⟨by grind, by grind, ?_, Nat.mod_lt _ hP, by grind, ?_⟩
  · rw [hex, hnb]
    exact (Nat.div_lt_iff_lt_mul hP).2 (by rw [← hBP]; exact Nat.mod_lt _ hBpos)
  · rw [hnb, ← hB, hex]
    have hr : d % B = d % B / 2 ^ p * 2 ^ p + d % B % 2 ^ p := (Nat.div_add_mod' _ _).symm
    simp only [postfixBits, ← hrmod]
    have : 2 + prefixBit d = d / B := by grind
    rw [this]
    grind

/-- The fields the decoder reads back out of an emitted symbol. -/
theorem symbol_fields (p nd d : Nat) (hd : 2 ^ (p + 2) ≤ d) :
    let code := symbol p nd d - 16 - nd
    16 + nd ≤ symbol p nd d ∧ code / 2 ^ p % 2 = prefixBit d ∧ code % 2 ^ p = postfixBits p d ∧
    1 + code / 2 ^ (p + 1) = nbits p d := by
  obtain ⟨hn, hpre, -, hpost, -, -⟩ := decompose p d hd
  have hP : 0 < 2 ^ p := Nat.two_pow_pos _
  have hcode : symbol p nd d - 16 - nd = 2 ^ p * (2 * (nbits p d - 1) + prefixBit d) + postfixBits p d := by
    simp only [symbol]; grind
  have hdiv : (symbol p nd d - 16 - nd) / 2 ^ p = 2 * (nbits p d - 1) + prefixBit d := by
    rw [hcode, Nat.mul_add_div hP, Nat.div_eq_of_lt hpost]; grind
  refine ⟨by simp only [symbol]; grind, ?_, ?_, ?_⟩
  · rw [hdiv]; grind
  · rw [hcode, Nat.mul_add_mod, Nat.mod_eq_of_lt hpost]
  · rw [Nat.pow_succ, ← Nat.div_div_eq_div_mul, hdiv]; grind

/-- Decoding what the encoder emits gives the distance back. -/
theorem decode_symbol (p nd d : Nat) (hd : 2 ^ (p + 2) ≤ d) :
    16 + nd ≤ symbol p nd d ∧ width p nd (symbol p nd d) = nbits p d ∧
    extra p d < 2 ^ width p nd (symbol p nd d) ∧
    decode p nd (symbol p nd d) (extra p d) + 2 ^ (p + 2) = d + nd + 1 := by
  obtain ⟨hn, hpre, hex, hpost, -, hd'⟩ := decompose p d hd
  obtain ⟨hge, hbit, hlow, hwidth⟩ := symbol_fields p nd d hd
  have hlt : ¬ symbol p nd d < 16 + nd := by grind
  have hw : width p nd (symbol p nd d) = nbits p d := by simp only [width, hlt, ite_false]; exact hwidth
  refine ⟨hge, hw, by rw [hw]; exact hex, ?_⟩
  simp only [decode, hlt, ite_false, hwidth, hbit, hlow]
  have h4 : 4 ≤ (2 + prefixBit d) * 2 ^ nbits p d := by
    have : 2 ≤ 2 ^ nbits p d := by
      calc 2 = 2 ^ 1 := by norm_num
        _ ≤ 2 ^ nbits p d := Nat.pow_le_pow_right (by decide) hn
    grind
  have hsplit : 2 ^ (nbits p d + p) = 2 ^ nbits p d * 2 ^ p := Nat.pow_add _ _ _
  have h4p : 2 ^ (p + 2) = 4 * 2 ^ p := by rw [Nat.pow_add]; ring
  rw [h4p]
  rw [hsplit] at hd'
  obtain ⟨k, hk⟩ : ∃ k, (2 + prefixBit d) * 2 ^ nbits p d = k + 4 := ⟨_, (Nat.sub_add_cancel h4).symm⟩
  rw [hk, Nat.add_sub_cancel]
  set e := extra p d
  set q := postfixBits p d
  have : d = (k + 4) * 2 ^ p + e * 2 ^ p + q := by
    rw [← hk]; nth_rewrite 1 [hd']; ring
  clear_value e q
  subst this; ring

/-- A distance below `2 ^ (n + p + 2)` needs at most `n` extra bits, so its symbol
stays inside an alphabet of `2 * n` buckets. -/
theorem symbol_lt (p nd d n : Nat) (hd : 2 ^ (p + 2) ≤ d) (hlt : d < 2 ^ (n + p + 2)) :
    nbits p d ≤ n ∧ symbol p nd d < 16 + nd + 2 * n * 2 ^ p := by
  obtain ⟨hn, hpre, -, hpost, hlog, -⟩ := decompose p d hd
  have hl : Nat.log 2 d < n + p + 2 := Nat.log_lt_of_lt_pow (by grind) hlt
  have hnb : nbits p d ≤ n := by grind
  refine ⟨hnb, ?_⟩
  have : (2 * (nbits p d - 1) + prefixBit d) * 2 ^ p + postfixBits p d < 2 * n * 2 ^ p := by
    have h1 : 2 * (nbits p d - 1) + prefixBit d + 1 ≤ 2 * n := by grind
    calc (2 * (nbits p d - 1) + prefixBit d) * 2 ^ p + postfixBits p d
        < (2 * (nbits p d - 1) + prefixBit d) * 2 ^ p + 2 ^ p := by grind
      _ = (2 * (nbits p d - 1) + prefixBit d + 1) * 2 ^ p := by ring
      _ ≤ 2 * n * 2 ^ p := Nat.mul_le_mul_right _ h1
  simp only [symbol]; grind

/-- The converse of `decompose`: a value written in the bucket form has exactly
those fields, so the split the encoder computes is the only one. -/
theorem split_unique (p n b e q : Nat) (hn : 1 ≤ n) (hb : b < 2) (he : e < 2 ^ n) (hq : q < 2 ^ p) :
    let d := (2 + b) * 2 ^ (n + p) + e * 2 ^ p + q
    nbits p d = n ∧ prefixBit d = b ∧ extra p d = e ∧ postfixBits p d = q := by
  intro d
  have hP : 0 < 2 ^ p := Nat.two_pow_pos _
  have hnp : 2 ^ (n + p) = 2 ^ n * 2 ^ p := Nat.pow_add _ _ _
  have hlow : e * 2 ^ p + q < 2 ^ (n + p) := by
    have : (e + 1) * 2 ^ p ≤ 2 ^ n * 2 ^ p := Nat.mul_le_mul_right _ he
    rw [hnp]; grind
  have hd : d = (2 + b) * 2 ^ (n + p) + (e * 2 ^ p + q) := by simp only [d]; ring
  have hlo : 2 ^ (n + p + 1) ≤ d := by
    rw [Nat.pow_succ, hd]
    calc 2 ^ (n + p) * 2 ≤ (2 + b) * 2 ^ (n + p) := by rw [Nat.mul_comm]; exact Nat.mul_le_mul_right _ (by grind)
      _ ≤ _ := Nat.le_add_right _ _
  have hhi : d < 2 ^ (n + p + 1 + 1) := by
    rw [Nat.pow_succ, Nat.pow_succ, hd]
    calc (2 + b) * 2 ^ (n + p) + (e * 2 ^ p + q) < (2 + b) * 2 ^ (n + p) + 2 ^ (n + p) :=
          Nat.add_lt_add_left hlow _
      _ = (3 + b) * 2 ^ (n + p) := by ring
      _ ≤ 4 * 2 ^ (n + p) := Nat.mul_le_mul_right _ (by grind)
      _ = 2 ^ (n + p) * 2 * 2 := by ring
  have hlog : Nat.log 2 d = n + p + 1 := Nat.log_eq_of_pow_le_of_lt_pow hlo hhi
  have hb' : Nat.log 2 d - 1 = n + p := by grind
  have hdiv : d / 2 ^ (n + p) = 2 + b := by
    rw [hd, Nat.mul_comm, Nat.mul_add_div (Nat.two_pow_pos _), Nat.div_eq_of_lt hlow]; rfl
  have hpre : prefixBit d = b := by simp only [prefixBit, hb', hdiv]; grind
  refine ⟨by simp only [nbits, hlog]; grind, hpre, ?_, ?_⟩
  · simp only [extra, hb', hpre]
    have : d - (2 + b) * 2 ^ (n + p) = 2 ^ p * e + q := by rw [hd]; grind
    rw [this, Nat.mul_add_div hP, Nat.div_eq_of_lt hq]; rfl
  · simp only [postfixBits]
    rw [show d = 2 ^ p * ((2 + b) * 2 ^ n + e) + q by rw [hd, hnp]; ring,
      Nat.mul_add_mod, Nat.mod_eq_of_lt hq]

/-- The value an explicit symbol and its extra field encode, before the decoder
removes the `4 << p` offset. -/
def encoded (p nd sym ex : Nat) : Nat := decode p nd sym ex + 2 ^ (p + 2) - nd - 1

/-- The encoder inverts the decoder: re-encoding what any valid explicit symbol
and extra field decode to gives that same symbol and field back. -/
theorem encode_decode (p nd sym ex : Nat) (h16 : 16 + nd ≤ sym) (hex : ex < 2 ^ width p nd sym) :
    2 ^ (p + 2) ≤ encoded p nd sym ex ∧
    symbol p nd (encoded p nd sym ex) = sym ∧ extra p (encoded p nd sym ex) = ex := by
  have hlt : ¬ sym < 16 + nd := by grind
  have hP : 0 < 2 ^ p := Nat.two_pow_pos _
  obtain ⟨c, hc⟩ : ∃ c, sym - 16 - nd = c := ⟨_, rfl⟩
  obtain ⟨h, hh⟩ : ∃ h, c / 2 ^ p = h := ⟨_, rfl⟩
  have hhw : c / 2 ^ (p + 1) = h / 2 := by rw [← hh, Nat.pow_succ, Nat.div_div_eq_div_mul]
  have hdec : decode p nd sym ex =
      ((2 + h % 2) * 2 ^ (1 + h / 2) - 4 + ex) * 2 ^ p + c % 2 ^ p + nd + 1 := by
    simp only [decode, hlt, ite_false, hc, hhw, hh]
  have hwid : width p nd sym = 1 + h / 2 := by simp only [width, hlt, ite_false, hc, hhw]
  rw [hwid] at hex
  have hsym : sym = 16 + nd + h * 2 ^ p + c % 2 ^ p := by
    have := Nat.div_add_mod' c (2 ^ p); rw [hh] at this; grind
  generalize hw : 1 + h / 2 = w at hdec hex
  generalize hq : c % 2 ^ p = q at hdec hsym
  have hqlt : q < 2 ^ p := by rw [← hq]; exact Nat.mod_lt _ hP
  have hw1 : 1 ≤ w := by grind
  have hhb : h = 2 * (w - 1) + h % 2 := by grind
  generalize hb : h % 2 = b at hdec hhb
  have hb2 : b < 2 := by rw [← hb]; exact Nat.mod_lt _ (by decide)
  have h4 : 4 ≤ (2 + b) * 2 ^ w := by
    have : 2 ≤ 2 ^ w := by
      calc 2 = 2 ^ 1 := by norm_num
        _ ≤ 2 ^ w := Nat.pow_le_pow_right (by decide) hw1
    calc 4 = 2 * 2 := by norm_num
      _ ≤ (2 + b) * 2 ^ w := Nat.mul_le_mul (by grind) this
  have henc : encoded p nd sym ex = (2 + b) * 2 ^ (w + p) + ex * 2 ^ p + q := by
    simp only [encoded, hdec]
    obtain ⟨k, hk⟩ : ∃ k, (2 + b) * 2 ^ w = k + 4 := ⟨_, (Nat.sub_add_cancel h4).symm⟩
    rw [hk, Nat.add_sub_cancel, show 2 ^ (p + 2) = 4 * 2 ^ p by rw [Nat.pow_add]; ring, Nat.pow_add 2 w p]
    rw [show (2 + b) * (2 ^ w * 2 ^ p) = (k + 4) * 2 ^ p by rw [← hk]; ring]
    grind
  obtain ⟨hn, hpre, he, hpost⟩ := split_unique p w b ex q hw1 hb2 hex hqlt
  rw [← henc] at hn hpre he hpost
  refine ⟨?_, ?_, he⟩
  · rw [henc]
    have : 2 ^ (p + 2) ≤ 2 * 2 ^ (w + p) := by
      rw [← Nat.pow_succ']; exact Nat.pow_le_pow_right (by decide) (by grind)
    have : 2 * 2 ^ (w + p) ≤ (2 + b) * 2 ^ (w + p) := Nat.mul_le_mul_right _ (by grind)
    grind
  · simp only [symbol, hn, hpre, hpost]
    rw [hsym, ← hhb]

/-- Explicit distance codes are unambiguous: two valid symbols past the short
codes, with extra fields of the width each reads, that decode to the same
distance are the same symbol with the same field. Direct codes decode to at most
`nd`, every other symbol to more, so the two kinds never collide. -/
theorem decode_injective (p nd s₁ e₁ s₂ e₂ : Nat) (h₁ : 16 ≤ s₁) (h₂ : 16 ≤ s₂)
    (he₁ : e₁ < 2 ^ width p nd s₁) (he₂ : e₂ < 2 ^ width p nd s₂)
    (hd : decode p nd s₁ e₁ = decode p nd s₂ e₂) : s₁ = s₂ ∧ e₁ = e₂ := by
  /- A symbol past the direct codes decodes above `nd`. -/
  have above : ∀ s e, 16 + nd ≤ s → e < 2 ^ width p nd s → nd < decode p nd s e := by
    intro s e hs he
    obtain ⟨hlo, -, -⟩ := encode_decode p nd s e hs he
    simp only [encoded] at hlo
    grind
  have direct : ∀ s e, 16 ≤ s → s < 16 + nd → e < 2 ^ width p nd s →
      e = 0 ∧ decode p nd s e = s - 15 := by
    intro s e hs hlt he
    simp only [width, hlt, ite_true, pow_zero] at he
    simp only [decode, hlt, ite_true]
    grind
  by_cases d₁ : s₁ < 16 + nd
  · by_cases d₂ : s₂ < 16 + nd
    · obtain ⟨z₁, v₁⟩ := direct s₁ e₁ h₁ d₁ he₁
      obtain ⟨z₂, v₂⟩ := direct s₂ e₂ h₂ d₂ he₂
      grind
    · have := above s₂ e₂ (by grind) he₂
      have := direct s₁ e₁ h₁ d₁ he₁
      grind
  · by_cases d₂ : s₂ < 16 + nd
    · have := above s₁ e₁ (by grind) he₁
      have := direct s₂ e₂ h₂ d₂ he₂
      grind
    · obtain ⟨-, hs₁, hx₁⟩ := encode_decode p nd s₁ e₁ (by grind) he₁
      obtain ⟨-, hs₂, hx₂⟩ := encode_decode p nd s₂ e₂ (by grind) he₂
      simp only [encoded, hd] at hs₁ hx₁
      exact ⟨hs₁.symm.trans hs₂, hx₁.symm.trans hx₂⟩

end Mbrotli.Model

end
