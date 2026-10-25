import Mbrotli.Basic
import Mbrotli.Rfc

/-! # The ring of the four last distances (RFC 7932 section 4)

`Cache` in `decompressor/core/distance.rs` keeps the four last distances in a
four-slot array and a push counter; the slot `(index - 1 - k) & 3` holds the
`k`-th most recent one. `Cache.ring` reads the four distances off, most recent
first, so the specifications below can state the RFC's ring operations
directly.
-/

open Aeneas Aeneas.Std Result
open Mbrotli.Rfc

namespace mbrotli
open decompressor.core.distance

/-- The `k`-th most recent distance, `k < 4`. -/
def decompressor.core.distance.Cache.recentNat (c : Cache) (k : Nat) : Nat :=
  (c.slots[(c.index.val + 3 - k) % 4]!).val

/-- The four last distances, most recent first. -/
def decompressor.core.distance.Cache.ring (c : Cache) : List Nat := [c.recentNat 0, c.recentNat 1, c.recentNat 2, c.recentNat 3]

theorem usize_size_dvd_four : 4 ∣ Usize.size := by
  rw [Usize.size_def, Usize.numBits_def, UScalarTy.Usize_numBits_eq]
  have := numBits_ge
  exact ⟨2 ^ (System.Platform.numBits - 2), by
    rw [show (4 : Nat) = 2 ^ 2 from rfl, ← Nat.pow_add]; congr 1; agrind⟩

/-- A wrapping subtraction of at most four, read modulo four. -/
theorem wrapping_sub_mod_four (x y : Nat) (hy : y ≤ 4) :
    (x + (Usize.size - y)) % Usize.size % 4 = (x + 4 - y) % 4 := by
  have hd := usize_size_dvd_four
  have : 4 ≤ Usize.size := by have := usize_size_ge; agrind
  rw [Nat.mod_mod_of_dvd _ hd]
  obtain ⟨m, hm⟩ := hd
  rw [hm]
  grind

theorem mod_four_lt (x : Nat) : x % 4 < 4 := Nat.mod_lt _ (by decide)

/-- **Spec theorem for `Cache::recent`**: the `back`-th most recent distance. -/
@[step]
theorem Cache.recent.spec (self : Cache) (back : Usize) (h : back.val < 4) :
    self.recent back ⦃ (r : U64) => r.val = self.recentNat back.val ⦄ := by
  unfold Cache.recent
  step as ⟨ i, i_post ⟩
  step as ⟨ i1, i1_post ⟩
  step as ⟨ i2, i2_post ⟩
  have hi2 : i2.val = (self.index.val + 3 - back.val) % 4 := by
    rw [i2_post, UScalar.val_and, show (3#usize : Usize).val = 2 ^ 2 - 1 from rfl,
      Nat.and_two_pow_sub_one_eq_mod, i1_post, core.num.Usize.wrapping_sub_val_eq, i_post,
      UScalar.size_UScalarTyUsize, show (2 : Nat) ^ 2 = 4 from rfl, wrapping_sub_mod_four _ _ (by agrind)]
    grind
  step as ⟨ r, r_post ⟩
  rw [r_post, List.Inhabited_getElem_eq_getElem!, hi2, ← Array.getElem!_Nat_eq]
  · rfl
  · scalar_tac

theorem wrapping_add_one_mod_four (x : Nat) : (x + 1) % Usize.size % 4 = (x + 1) % 4 :=
  Nat.mod_mod_of_dvd _ usize_size_dvd_four

/-- **Spec theorem for `Cache::push`**: the distance becomes the most recent,
the others move back one place and the oldest drops off. -/
@[step]
theorem Cache.push.spec (self : Cache) (distance : U64) :
    self.push distance ⦃ (c : Cache) => c.ring = distance.val :: self.ring.take 3 ⦄ := by
  unfold Cache.push
  step as ⟨ i, i_post ⟩
  have hi : i.val = self.index.val % 4 := by
    rw [i_post, UScalar.val_and, show (3#usize : Usize).val = 2 ^ 2 - 1 from rfl,
      Nat.and_two_pow_sub_one_eq_mod]
  step as ⟨ a, a_post ⟩
  step as ⟨ i1, i1_post ⟩
  have hidx : ∀ k ≤ 3, (i1.val + 3 - k) % 4 = (self.index.val + 4 - k) % 4 := by
    intro k hk
    rw [i1_post, core.num.Usize.wrapping_add_val_eq, show (1#usize : Usize).val = 1 from rfl,
      UScalar.size_UScalarTyUsize]
    have := wrapping_add_one_mod_four self.index.val
    grind
  simp only [Cache.ring, Cache.recentNat, List.take]
  rw [hidx 0 (by decide), hidx 1 (by decide), hidx 2 (by decide), hidx 3 (by decide), a_post]
  have hget : ∀ j, j < 4 → (self.slots.set i distance)[j]! =
      if j = self.index.val % 4 then distance else self.slots[j]! := by
    intro j hj
    by_cases h : j = self.index.val % 4
    · simp only [h, ite_true]
      exact Array.getElem!_Nat_set_eq _ _ _ _ ⟨by rw [hi], by scalar_tac⟩
    · simp only [h, ite_false]
      exact Array.getElem!_Nat_set_ne _ _ _ _ (by rw [hi]; exact Ne.symm h)
  rw [hget _ (mod_four_lt _), hget _ (mod_four_lt _), hget _ (mod_four_lt _), hget _ (mod_four_lt _)]
  have e0 : (self.index.val + 4 - 0) % 4 = self.index.val % 4 := by grind
  have n1 : ¬ (self.index.val + 3 - 0) % 4 = self.index.val % 4 := by grind
  have n2 : ¬ (self.index.val + 3 - 1) % 4 = self.index.val % 4 := by grind
  have n3 : ¬ (self.index.val + 3 - 2) % 4 = self.index.val % 4 := by grind
  have m1 : (self.index.val + 4 - 1) % 4 = (self.index.val + 3 - 0) % 4 := by grind
  have m2 : (self.index.val + 4 - 2) % 4 = (self.index.val + 3 - 1) % 4 := by grind
  have m3 : (self.index.val + 4 - 3) % 4 = (self.index.val + 3 - 2) % 4 := by grind
  simp only [e0, m1, m2, m3, n1, n2, n3, ite_true, ite_false]

/-- **Spec theorem for `Cache::pop`**: takes the most recent distance out and
rotates it behind the others, so that a following `push` replaces it. -/
@[step]
theorem Cache.pop.spec (self : Cache) :
    self.pop ⦃ (d : U64) (c : Cache) =>
      d.val = self.recentNat 0 ∧ c.ring = self.ring.tail ++ [self.recentNat 0] ⦄ := by
  unfold Cache.pop
  step as ⟨ i, i_post ⟩
  have hidx : ∀ k ≤ 3, (i.val + 3 - k) % 4 = (self.index.val + 6 - k) % 4 := by
    intro k hk
    rw [i_post, core.num.Usize.wrapping_sub_val_eq, show (1#usize : Usize).val = 1 from rfl,
      UScalar.size_UScalarTyUsize]
    have := wrapping_sub_mod_four self.index.val 1 (by decide)
    grind
  step as ⟨ i1, i1_post ⟩
  have hi1 : i1.val = (self.index.val + 3) % 4 := by
    rw [i1_post, UScalar.val_and, show (3#usize : Usize).val = 2 ^ 2 - 1 from rfl,
      Nat.and_two_pow_sub_one_eq_mod, i_post, core.num.Usize.wrapping_sub_val_eq,
      show (1#usize : Usize).val = 1 from rfl, UScalar.size_UScalarTyUsize,
      show (2 : Nat) ^ 2 = 4 from rfl, wrapping_sub_mod_four _ _ (by decide)]
    grind
  step as ⟨ d, d_post ⟩
  refine ⟨?_, ?_⟩
  · rw [d_post, List.Inhabited_getElem_eq_getElem!, hi1, ← Array.getElem!_Nat_eq]
    · rfl
    · scalar_tac
  · simp only [Cache.ring, Cache.recentNat, List.tail, List.cons_append, List.nil_append]
    rw [hidx 0 (by decide), hidx 1 (by decide), hidx 2 (by decide), hidx 3 (by decide)]
    have e : ∀ k ≤ 2, (self.index.val + 6 - k) % 4 = (self.index.val + 3 - (k + 1)) % 4 := by
      intro k hk; grind
    have e3 : (self.index.val + 6 - 3) % 4 = (self.index.val + 3 - 0) % 4 := by grind
    rw [e 0 (by decide), e 1 (by decide), e 2 (by decide), e3]

/-- **Spec theorem for `<Cache as Default>::default`**: the ring the stream
starts with (RFC 7932 section 4). -/
@[step]
theorem Cache.default.spec :
    Cache.Insts.CoreDefaultDefault.default ⦃ (c : Cache) => c.ring = initialRing ⦄ := by
  unfold Cache.Insts.CoreDefaultDefault.default
  simp only [WP.spec_ok, Cache.ring, Cache.recentNat, initialRing]
  decide

/-- `pop` followed by `push` replaces the most recent distance and keeps the
others: the decoder's way of writing a distance without growing the ring. -/
theorem Cache.pop_push (self : Cache) (y : U64) :
    self.pop ⦃ (_d : U64) (c : Cache) => c.push y ⦃ (c' : Cache) => c'.ring = y.val :: self.ring.tail ⦄ ⦄ := by
  apply WP.spec_mono (Cache.pop.spec self)
  rintro ⟨d, c⟩ ⟨-, hring⟩
  apply WP.spec_mono (Cache.push.spec c y)
  intro c' hc'
  rw [hc', hring]
  simp [Cache.ring]

end mbrotli
