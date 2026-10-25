import Mbrotli.DecoderDistance
import Mbrotli.DistanceCache

/-! # Resolving every distance symbol (RFC 7932 section 4)

`DistanceLayout::short` resolves the sixteen short symbols against the ring of
last distances, `resolve` dispatches between them and the explicit codes, and
`validate_symbol` is the header check that makes the explicit large-window
path safe. Each is shown to compute what section 4 prescribes.

`short` rejects distances above `2^63 - 4` as well as the zero and negative
ones the RFC rejects. The upper bound is an implementation limit, stricter
than the RFC: no window or dictionary reference reaches it.
-/

open Aeneas Aeneas.Std Result
open Mbrotli.Rfc

namespace mbrotli
open decompressor.core.distance

/-- The largest distance the decoder accepts. -/
def maxDistance : Nat := 2 ^ 63 - 4

theorem MAX_DISTANCE_U64.spec :
    MAX_DISTANCE_U64 ⦃ (x : U64) => x.val = maxDistance ⦄ := by
  rw [MAX_DISTANCE_U64]
  step*
  rw [x_post, i_post, maxDistance, Nat.one_shiftLeft,
    Nat.mod_eq_of_lt (by rw [show U64.size = 2 ^ 64 by simp [U64.size, U64.numBits]]; decide)]

theorem MAX_DISTANCE.spec :
    MAX_DISTANCE ⦃ (x : U128) => x.val = maxDistance ⦄ := by
  rw [MAX_DISTANCE]
  step*
  rw [x_post, i_post, maxDistance, Nat.one_shiftLeft,
    Nat.mod_eq_of_lt (by rw [show U128.size = 2 ^ 128 by simp [U128.size, U128.numBits]]; decide)]

theorem short_INDEX_val :
    ∀ i < 16, (DistanceLayout.short.INDEX.val[i]!).val = (shortCodes.getD i (0, 0)).1 := by
  rw [DistanceLayout.short.INDEX]
  decide +kernel

theorem short_OFFSET_val :
    ∀ i < 16, (DistanceLayout.short.OFFSET.val[i]!).val = (shortCodes.getD i (0, 0)).2 := by
  rw [DistanceLayout.short.OFFSET]
  decide +kernel

/-- The value RFC 7932 section 4 gives short symbol `s` for a ring of last
distances, most recent first. -/
def shortValue (ring : List Nat) (s : Nat) : Int :=
  (ring.getD (shortCodes.getD s (0, 0)).1 0 : Int) + (shortCodes.getD s (0, 0)).2

/-- The range the decoder accepts. -/
def InRange (v : Int) : Prop := 0 < v ∧ v ≤ maxDistance

/-- The error every rejected distance raises. -/
def distanceError : decompressor.error.DecodeError :=
  .InvalidData .Distance

@[simp]
theorem into_distance_error :
    core.convert.IntoFrom.into decompressor.error.DecodeError.Insts.CoreConvertFromInvalidDataKind
      decompressor.error.InvalidDataKind.Distance = ok distanceError := rfl

@[simp]
theorem from_distance_error :
    decompressor.error.DecodeError.Insts.CoreConvertFromInvalidDataKind.from
      decompressor.error.InvalidDataKind.Distance = ok distanceError := rfl

/-- The closure that keeps a distance in range, then the error for none. -/
theorem short_tail.spec (o : Option U64) :
    (do
      let o1 ← core.option.Option.filter
        DistanceLayout.short.closure.Insts.CoreOpsFunctionFnOnceTupleShared0U64Bool o ()
      core.option.Option.ok_or_else
        DistanceLayout.short.closure_1.Insts.CoreOpsFunctionFnOnceTupleDecodeError o1 ()) ⦃
      (r : core.result.Result U64 decompressor.error.DecodeError) =>
        match r with
        | .Ok d => o = some d ∧ InRange d.val
        | .Err e => e = distanceError ∧ ∀ d, o = some d → ¬ InRange d.val ⦄ := by
  cases o
  · /- No sum: the error. -/
    simp only [core.option.Option.filter, core.option.Option.ok_or_else, Std.bind_ok,
      DistanceLayout.short.closure_1.Insts.CoreOpsFunctionFnOnceTupleDecodeError.call_once]
    simp
  · rename_i d
    simp only [core.option.Option.filter, core.option.Option.ok_or_else,
      DistanceLayout.short.closure.Insts.CoreOpsFunctionFnOnceTupleShared0U64Bool.call_once,
      DistanceLayout.short.closure_1.Insts.CoreOpsFunctionFnOnceTupleDecodeError.call_once,
      into_distance_error]
    split
    · rename_i hne
      have hd0 : d.val ≠ 0 := fun h0 => by
        simp only [bne_iff_ne, ne_eq] at hne; exact hne (UScalar.eq_of_val_eq (by rw [h0]; rfl))
      step with MAX_DISTANCE_U64.spec as ⟨ m, hm ⟩
      by_cases hle : d ≤ m
      · have hv : d.val ≤ maxDistance := by rw [← hm]; exact (UScalar.le_equiv _ _).mp hle
        simp only [decide_eq_true hle, ite_true, WP.spec_ok]
        exact ⟨trivial, by agrind, by agrind⟩
      · have hv : ¬ d.val ≤ maxDistance := fun h => hle ((UScalar.le_equiv _ _).mpr (by rw [hm]; exact h))
        simp only [decide_eq_false hle, Bool.false_eq_true, ite_false, WP.spec_ok]
        refine ⟨trivial, ?_⟩
        intro d1 h1
        simp only [Option.some.injEq] at h1
        subst h1
        simp only [InRange]; agrind
    · rename_i hz
      have hd0 : d.val = 0 := by
        simp only [bne_iff_ne, ne_eq, Decidable.not_not] at hz; rw [hz]; rfl
      simp only [Std.bind_ok, Bool.false_eq_true, ite_false, WP.spec_ok]
      refine ⟨trivial, ?_⟩
      intro d1 h1
      simp only [Option.some.injEq] at h1
      subst h1
      simp only [InRange]; agrind

/-- `i64::from(i8)` keeps the value. -/
@[local step]
theorem from_i64_i8.spec (x : I8) :
    lift (core.convert.num.FromI64I8.from x) ⦃ (y : I64) => y.val = x.val ⦄ := by
  simp only [lift, WP.spec_ok, core.convert.num.FromI64I8.from_val_eq]

theorem Cache.ring_getD (c : Cache) (k : Nat) (hk : k < 4) : c.ring.getD k 0 = c.recentNat k := by
  have : k = 0 ∨ k = 1 ∨ k = 2 ∨ k = 3 := by agrind
  rcases this with rfl | rfl | rfl | rfl
  · rfl
  · rfl
  · rfl
  · rfl

/-- **Spec theorem for `DistanceLayout::short`**: a short symbol resolves to the
past distance plus the offset RFC 7932 section 4 lists for it, and is rejected
exactly when that value is not a positive distance the decoder accepts. -/
@[step]
theorem DistanceLayout.short.spec (symbol : Usize) (cache : Cache) (h : symbol.val < 16) :
    DistanceLayout.short symbol cache ⦃ (r : core.result.Result U64 decompressor.error.DecodeError) =>
      match r with
      | .Ok d => (d.val : Int) = shortValue cache.ring symbol.val ∧ InRange (shortValue cache.ring symbol.val)
      | .Err e => e = distanceError ∧ ¬ InRange (shortValue cache.ring symbol.val) ⦄ := by
  have := numBits_ge
  have hidx : ∀ i < 16, (shortCodes.getD i (0, 0)).1 < 4 := by decide
  unfold DistanceLayout.short
  step as ⟨ i, i_post ⟩
  have hi : i.val = symbol.val := by
    rw [i_post, UScalar.val_and, show (15#usize : Usize).val = 2 ^ 4 - 1 from rfl,
      Nat.and_two_pow_sub_one_eq_mod, Nat.mod_eq_of_lt h]
  step as ⟨ i1, i1_post ⟩
  have hi1 : i1.val = (shortCodes.getD symbol.val (0, 0)).1 := by
    rw [i1_post, List.Inhabited_getElem_eq_getElem!, hi]
    · exact short_INDEX_val _ h
    · have := DistanceLayout.short.INDEX.property; agrind
  step with Cache.recent.spec cache i1 (by rw [hi1]; exact hidx _ h) as ⟨ i2, i2_post ⟩
  step as ⟨ i3, i3_post ⟩
  step as ⟨ i4, i4_post ⟩
  have hi4 : i4.val = (shortCodes.getD symbol.val (0, 0)).2 := by
    have hi3 : i3.val = symbol.val := by
      rw [i3_post, UScalar.val_and, show (15#usize : Usize).val = 2 ^ 4 - 1 from rfl,
        Nat.and_two_pow_sub_one_eq_mod, Nat.mod_eq_of_lt h]
    rw [i4_post, List.Inhabited_getElem_eq_getElem!, hi3]
    · exact short_OFFSET_val _ h
    · have := DistanceLayout.short.OFFSET.property; agrind
  step as ⟨ i5, i5_post ⟩
  have hv : (i2.val : Int) + i5.val = shortValue cache.ring symbol.val := by
    rw [i2_post, i5_post, hi4, hi1, shortValue, Cache.ring_getD _ _ (hidx _ h)]
  /- The sum, if it lies in `0..=u64::MAX`. -/
  simp only [core.num.U64.checked_add_signed]
  split
  · rename_i hfit
    simp only [Std.bind_ok]
    apply WP.spec_mono (short_tail.spec _)
    intro r hr
    have hU : (U64.max : Int) < 2 ^ 64 := by simp [U64.max, U64.numBits]
    have hw : ((⟨BitVec.ofNat 64 ((i2.val : Int) + i5.val).toNat⟩ : U64).val : Int) = i2.val + i5.val := by
      show ((BitVec.ofNat 64 _).toNat : Int) = _
      rw [BitVec.toNat_ofNat, Nat.mod_eq_of_lt (by agrind), Int.toNat_of_nonneg hfit.1]
    rw [← hv]
    cases r
    · rename_i d
      obtain ⟨hd, hin⟩ := hr
      simp only [Option.some.injEq] at hd
      rw [← hd] at hin ⊢
      rw [hw] at hin
      exact ⟨hw, hin⟩
    · obtain ⟨he, hno⟩ := hr
      refine ⟨he, ?_⟩
      have := hno _ rfl
      rw [hw] at this
      exact this
  · rename_i hfit
    simp only [Std.bind_ok]
    apply WP.spec_mono (short_tail.spec _)
    intro r hr
    rw [← hv]
    have hU : (maxDistance : Int) ≤ U64.max := by simp [maxDistance, U64.max, U64.numBits]
    cases r
    · obtain ⟨hd, -⟩ := hr
      exact absurd hd (by simp)
    · obtain ⟨he, -⟩ := hr
      refine ⟨he, ?_⟩
      simp only [InRange]
      agrind

/-- **Spec theorem for `DistanceLayout::resolve_large`**: the RFC distance of
an explicit large-window symbol when it fits in 64 bits, the distance error
otherwise. -/
@[step]
theorem DistanceLayout.resolve_large.spec (self : DistanceLayout) (symbol : Usize) (extra : U64)
    (hp : self.postfix.val ≤ 3) (hd : self.direct.val ≤ 120)
    (hs16 : 16 ≤ symbol.val) (hs : symbol.val < 16 + self.direct.val + 2 * 62 * 2 ^ self.postfix.val)
    (hx : extra.val < 2 ^ Mbrotli.Model.width self.postfix.val self.direct.val symbol.val) :
    self.resolve_large symbol extra ⦃ (r : core.result.Result U64 decompressor.error.DecodeError) =>
      match r with
      | .Ok d => d.val = Mbrotli.Model.decode self.postfix.val self.direct.val symbol.val extra.val
      | .Err e => e = distanceError ∧
          U64.max < Mbrotli.Model.decode self.postfix.val self.direct.val symbol.val extra.val ⦄ := by
  unfold DistanceLayout.resolve_large
  step as ⟨ i, i_post ⟩
  simp only [U64.Insts.CoreConvertTryFromU128TryFromIntError.try_from, core.num.tryFromUScalar]
  split
  · rename_i hfit
    simp only [Std.bind_ok, core.result.Result.map_err, WP.spec_ok]
    rw [UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), i_post]
  · rename_i hfit
    simp only [Std.bind_ok, core.result.Result.map_err,
      DistanceLayout.resolve_large.closure.Insts.CoreOpsFunctionFnOnceTupleTryFromIntErrorDecodeError.call_once,
      into_distance_error]
    step*

/-- RFC 7932 section 4's distance for any symbol of a layout: short symbols
against the ring of last distances, the others by the section 4 formula. -/
def rfcDistance (l : DistanceLayout) (ring : List Nat) (s ex : Nat) : Int :=
  if s < 16 then shortValue ring s else Mbrotli.Model.decode l.postfix.val l.direct.val s ex

/-- **Spec theorem for `DistanceLayout::resolve`**: for every symbol of the
layout's alphabet and every extra field of its width, the RFC distance, or the
distance error when a short symbol leaves the accepted range or a large-window
distance does not fit in 64 bits. -/
@[step]
theorem DistanceLayout.resolve.spec (self : DistanceLayout) (symbol : Usize) (extra : U64)
    (cache : Cache) (hp : self.postfix.val ≤ 3) (hd : self.direct.val ≤ 120)
    (hs : symbol.val < 16 + self.direct.val + 2 * (if self.large then 62 else 24) * 2 ^ self.postfix.val)
    (hx : 16 ≤ symbol.val → extra.val < 2 ^ Mbrotli.Model.width self.postfix.val self.direct.val symbol.val) :
    self.resolve symbol extra cache ⦃ (r : core.result.Result U64 decompressor.error.DecodeError) =>
      match r with
      | .Ok d => (d.val : Int) = rfcDistance self cache.ring symbol.val extra.val ∧
          (symbol.val < 16 → InRange (shortValue cache.ring symbol.val))
      | .Err e => e = distanceError ∧
          (if symbol.val < 16 then ¬ InRange (shortValue cache.ring symbol.val)
           else self.large ∧ U64.max < Mbrotli.Model.decode self.postfix.val self.direct.val symbol.val extra.val) ⦄ := by
  unfold DistanceLayout.resolve
  split
  · rename_i h16
    have h16' : 16 ≤ symbol.val := by scalar_tac
    have hlt : ¬ symbol.val < 16 := by agrind
    split
    · rename_i hl
      rw [hl] at hs
      simp only [ite_true] at hs
      apply WP.spec_mono (DistanceLayout.resolve_large.spec self symbol extra hp hd h16' hs (hx h16'))
      intro r hr
      cases r
      · simp only [rfcDistance, hlt, ite_false]
        exact ⟨by rw [hr], False.elim⟩
      · exact ⟨hr.1, hl, hr.2⟩
    · rename_i hl
      have hl' : self.large = false := by simpa using hl
      rw [hl'] at hs
      simp only [Bool.false_eq_true, ite_false] at hs
      step with DistanceLayout.short_window_distance.spec self symbol extra hp hd h16' hs (hx h16')
        as ⟨ d, hd' ⟩
      simp only [rfcDistance, hlt, ite_false]
      exact ⟨by rw [hd'], False.elim⟩
  · rename_i h16
    have h16' : symbol.val < 16 := by scalar_tac
    apply WP.spec_mono (DistanceLayout.short.spec symbol cache h16')
    intro r hr
    cases r
    · simp only [rfcDistance, h16', ite_true]
      exact ⟨hr.1, fun _ => hr.2⟩
    · simp only [h16', ite_true]
      exact hr

/-- A symbol the header accepts: inside the alphabet, and, past the short
codes, unable to reach a distance above the decoder's limit with any extra
field of its width. -/
def decompressor.core.distance.DistanceLayout.ValidSymbol (l : DistanceLayout) (s : Nat) : Prop :=
  s < 16 + l.direct.val + 2 * (if l.large then 62 else 24) * 2 ^ l.postfix.val ∧
  (16 ≤ s → Mbrotli.Model.decode l.postfix.val l.direct.val s
    (2 ^ Mbrotli.Model.width l.postfix.val l.direct.val s - 1) ≤ maxDistance)

/-- **Spec theorem for `DistanceLayout::validate_symbol`**. -/
@[step]
theorem DistanceLayout.validate_symbol.spec (self : DistanceLayout) (symbol : Usize)
    (hp : self.postfix.val ≤ 3) (hd : self.direct.val ≤ 120) :
    self.validate_symbol symbol ⦃ (r : core.result.Result Unit decompressor.error.DecodeError) =>
      match r with
      | .Ok _ => self.ValidSymbol symbol.val
      | .Err e => e = distanceError ∧ ¬ self.ValidSymbol symbol.val ⦄ := by
  have := numBits_ge
  unfold DistanceLayout.validate_symbol
  step as ⟨ a, a_post ⟩
  split
  · rename_i hge
    rw [from_distance_error]
    step*
    intro h
    have := h.1
    scalar_tac
  · rename_i hlt
    have hlt' : symbol.val < 16 + self.direct.val + 2 * (if self.large then 62 else 24) * 2 ^ self.postfix.val := by
      scalar_tac
    split
    · rename_i h16
      have h16' : 16 ≤ symbol.val := by scalar_tac
      have hP : 2 ^ self.postfix.val ≤ 8 := (two_pow_postfix_le _ hp).2
      have hlarge : symbol.val < 16 + self.direct.val + 2 * 62 * 2 ^ self.postfix.val := by
        have : (if self.large then 62 else 24) ≤ 62 := by
          by_cases hl : self.large
          · simp [hl]
          · simp [hl]
        have : 2 * (if self.large then 62 else 24) * 2 ^ self.postfix.val ≤ 2 * 62 * 2 ^ self.postfix.val :=
          Nat.mul_le_mul_right _ (Nat.mul_le_mul_left _ this)
        exact lt_of_lt_of_le hlt' (Nat.add_le_add_left this _)
      have hw : Mbrotli.Model.width self.postfix.val self.direct.val symbol.val ≤ 62 := by
        by_cases hdir : symbol.val < 16 + self.direct.val
        · simp [Mbrotli.Model.width, hdir]
        · exact (width_le self.postfix.val self.direct.val symbol.val 62 (by agrind) hlarge).1
      step with DistanceLayout.extra_bits.spec self symbol hp hd (by agrind) as ⟨ w, w_post ⟩
      step as ⟨ i2, i2_post ⟩
      have hi2 : i2.val = 2 ^ Mbrotli.Model.width self.postfix.val self.direct.val symbol.val := by
        rw [i2_post, Nat.one_shiftLeft, w_post, Nat.mod_eq_of_lt]
        rw [show U64.size = 2 ^ 64 by simp [U64.size, U64.numBits]]
        exact Nat.pow_lt_pow_right (by decide) (by agrind)
      step as ⟨ i3, i3_post ⟩
      · rw [hi2]; exact Nat.one_le_two_pow
      step with DistanceLayout.long_distance.spec self symbol i3 hp hd h16' hlarge
        (by rw [i3_post, hi2]; exact Nat.sub_lt (Nat.two_pow_pos _) (by decide)) as ⟨ i4, i4_post ⟩
      step with MAX_DISTANCE.spec as ⟨ i5, i5_post ⟩
      rw [i3_post, hi2] at i4_post
      split
      · rename_i hgt
        rw [from_distance_error]
        step*
        intro h
        have := h.2 h16'
        have : i5.val < i4.val := (UScalar.lt_equiv _ _).mp hgt
        agrind
      · rename_i hle
        simp only [WP.spec_ok]
        refine ⟨hlt', fun _ => ?_⟩
        have : ¬ i5.val < i4.val := fun h => hle ((UScalar.lt_equiv _ _).mpr h)
        agrind
    · rename_i h16
      have h16' : symbol.val < 16 := by scalar_tac
      simp only [WP.spec_ok]
      exact ⟨hlt', fun h => absurd h (by agrind)⟩

/-- The distance grows with the extra field, so the largest field gives the
largest distance a symbol can reach. -/
theorem decode_mono (p nd sym ex ex' : Nat) (h : ex ≤ ex') :
    Mbrotli.Model.decode p nd sym ex ≤ Mbrotli.Model.decode p nd sym ex' := by
  simp only [Mbrotli.Model.decode]
  split
  · exact le_rfl
  · have := Nat.mul_le_mul_right (2 ^ p) (Nat.add_le_add_left h
      ((2 + (sym - 16 - nd) / 2 ^ p % 2) * 2 ^ (1 + (sym - 16 - nd) / 2 ^ (p + 1)) - 4))
    agrind

/-- **The header check makes explicit distances total.** For a symbol
`validate_symbol` accepted, past the short codes, every extra field of its width
resolves to the RFC distance: the large-window conversion to `u64` cannot fail. -/
theorem validated_resolve (self : DistanceLayout) (symbol : Usize) (extra : U64) (cache : Cache)
    (hp : self.postfix.val ≤ 3) (hd : self.direct.val ≤ 120)
    (hv : self.ValidSymbol symbol.val) (h16 : 16 ≤ symbol.val)
    (hx : extra.val < 2 ^ Mbrotli.Model.width self.postfix.val self.direct.val symbol.val) :
    self.resolve symbol extra cache ⦃ (r : core.result.Result U64 decompressor.error.DecodeError) =>
      ∃ d, r = .Ok d ∧ d.val = Mbrotli.Model.decode self.postfix.val self.direct.val symbol.val extra.val ⦄ := by
  apply WP.spec_mono (DistanceLayout.resolve.spec self symbol extra cache hp hd hv.1 (fun _ => hx))
  have hlt : ¬ symbol.val < 16 := by agrind
  have hmax : Mbrotli.Model.decode self.postfix.val self.direct.val symbol.val extra.val ≤ maxDistance :=
    le_trans (decode_mono _ _ _ _ _ (by agrind)) (hv.2 h16)
  intro r hr
  cases r
  · rename_i d
    obtain ⟨hdv, -⟩ := hr
    simp only [rfcDistance, hlt, ite_false] at hdv
    exact ⟨d, rfl, by agrind⟩
  · obtain ⟨-, hbad⟩ := hr
    simp only [hlt, ite_false] at hbad
    have : maxDistance < U64.max := by simp [maxDistance, U64.max, U64.numBits]
    agrind

end mbrotli
