import Mbrotli.EncoderLength
import Mbrotli.DecoderCommands

/-! # Insert and copy lengths survive the trip from encoder to decoder

RFC 7932 section 5 carries an insert length and a copy length as one symbol and
two extra fields. For every pair of lengths the format can carry, the symbol the
encoder emits selects, in the decoder's command table, codes whose ranges hold
both lengths, with extra fields wide enough to reach them, and the distance
context section 7.2 assigns to the copy length. No other symbol with the same
implicit-distance flag describes the same pair.
-/

open Aeneas Aeneas.Std Result
open Mbrotli.Rfc

namespace mbrotli
open shared.command decompressor.core.stream

/-- Length code ranges never overlap: a length has one insert code. -/
theorem insert_code_unique (l c₁ c₂ : Nat) (h₁ : InsertCodeOf l c₁) (h₂ : InsertCodeOf l c₂) :
    c₁ = c₂ := by
  have mono : ∀ a < 24, ∀ b < 24, a < b → (row insertRows a).hi < (row insertRows b).lo := by
    decide
  obtain ⟨ha, hla, hha⟩ := h₁
  obtain ⟨hb, hlb, hhb⟩ := h₂
  by_contra hne
  rcases Nat.lt_or_gt_of_ne hne with hlt | hlt
  · have := mono _ ha _ hb hlt; agrind
  · have := mono _ hb _ ha hlt; agrind

/-- A length has one copy code. -/
theorem copy_code_unique (l c₁ c₂ : Nat) (h₁ : CopyCodeOf l c₁) (h₂ : CopyCodeOf l c₂) :
    c₁ = c₂ := by
  have mono : ∀ a < 24, ∀ b < 24, a < b → (row copyRows a).hi < (row copyRows b).lo := by
    decide
  obtain ⟨ha, hla, hha⟩ := h₁
  obtain ⟨hb, hlb, hhb⟩ := h₂
  by_contra hne
  rcases Nat.lt_or_gt_of_ne hne with hlt | hlt
  · have := mono _ ha _ hb hlt; agrind
  · have := mono _ hb _ ha hlt; agrind

/-- **Length codes round-trip.** For every insert length up to 16799809 and copy
length from 2 to 16779333, the entry of the decoder's command table for the
encoder's symbol holds both lengths: each is its base plus an extra field of the
entry's width. The entry also flags the implicit distance as the encoder asked
and gives the copy length's distance context. -/
theorem length_round_trip (insertlen copylen : Usize) (use_last_distance : Bool)
    (hi : insertlen.val ≤ 16799809) (h2 : 2 ≤ copylen.val) (hc : copylen.val ≤ 16779333) :
    length_code insertlen copylen use_last_distance ⦃ (s : U16) =>
      commands ⦃ (t : Array decompressor.core.stream.Command 1024#usize) =>
        t[s.val]!.insert_base.val ≤ insertlen.val ∧
        insertlen.val - t[s.val]!.insert_base.val < 2 ^ t[s.val]!.insert_extra.val ∧
        t[s.val]!.copy_base.val ≤ copylen.val ∧
        copylen.val - t[s.val]!.copy_base.val < 2 ^ t[s.val]!.copy_extra.val ∧
        t[s.val]!.implicit = (use_last_distance && decide (insertCode s.val < 8) &&
          decide (copyCode s.val < 16)) ∧
        t[s.val]!.distance_context.val = distanceContext copylen.val ⦄ ⦄ := by
  apply WP.spec_mono (length_code.spec insertlen copylen use_last_distance hi h2 hc)
  rintro s ⟨hs, ⟨hi24, hilo, hihi⟩, ⟨hc24, hclo, hchi⟩, himp⟩
  apply WP.spec_mono commands.spec
  intro t ht
  obtain ⟨hib, hie, hcb, hce, -, himpl, hctx⟩ := ht s.val hs
  have wi : ∀ c < 24, (row insertRows c).hi + 1 = (row insertRows c).lo + 2 ^ (row insertRows c).extra := by
    decide
  have wc : ∀ c < 24, (row copyRows c).hi + 1 = (row copyRows c).lo + 2 ^ (row copyRows c).extra := by
    decide
  have hwi := wi _ hi24
  have hwc := wc _ hc24
  rw [hib, hie, hcb, hce, himpl, hctx copylen.val hclo hchi, ← himp]
  exact ⟨hilo, by agrind, hclo, by agrind, rfl, rfl⟩

/-- **Length symbols are unique.** Every insert-and-copy length symbol whose RFC
codes cover the same insert and copy lengths, and which agrees on reusing the
last distance, is the encoder's symbol. Any encoder emitting this pair of
lengths with this distance choice therefore emits the same symbol. -/
theorem length_code_unique (insertlen copylen : Usize) (use_last_distance : Bool)
    (hi : insertlen.val ≤ 16799809) (h2 : 2 ≤ copylen.val) (hc : copylen.val ≤ 16779333) :
    length_code insertlen copylen use_last_distance ⦃ (s : U16) =>
      ∀ s' < commandSymbols, InsertCodeOf insertlen.val (insertCode s') →
        CopyCodeOf copylen.val (copyCode s') → implicitDistance s' = implicitDistance s.val →
        s' = s.val ⦄ := by
  apply WP.spec_mono (length_code.spec insertlen copylen use_last_distance hi h2 hc)
  rintro s ⟨hs, hins, hcp, -⟩ s' hs' hins' hcp' himp
  have hi' := insert_code_unique _ _ _ hins' hins
  have hc' := copy_code_unique _ _ _ hcp' hcp
  rw [← combineModel_inverse s' hs', ← combineModel_inverse s.val hs, hi', hc', himp]

end mbrotli
