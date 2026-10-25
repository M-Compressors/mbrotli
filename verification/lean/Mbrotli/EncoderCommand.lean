import Mbrotli.EncoderLength
import Mbrotli.DistanceRoundTrip
import Mbrotli.LengthRoundTrip

/-! # The encoder's commands carry RFC 7932 section 5 lengths

`Command` in `shared/command.rs` stores a command's insert length, its copy
length with a seven-bit signed delta to the length the decoder reconstructs,
and the insert-and-copy length symbol. This file shows that the symbol, the
extra bits and the distance context it produces are the ones section 5 and
section 7.2 prescribe for those lengths.

The translation is of the default feature set: the `experimental` branches of
`Command::new` and `Command::copy_len_code`, which store an absolute length for
long RFC 9841 transforms, are not covered.
-/

open Aeneas Aeneas.Std Result
open Mbrotli.Rfc

namespace mbrotli
open shared.command

@[simp, scalar_tac_simps, agrind =, grind =, bvify]
theorem shared.command.COPY_LEN_CODE_SHIFT_val : COPY_LEN_CODE_SHIFT.val = 25 := by
  simp [COPY_LEN_CODE_SHIFT]

@[simp, scalar_tac_simps, agrind =, grind =, bvify]
theorem shared.command.COPY_LEN_MASK_val : COPY_LEN_MASK.val = 2 ^ 25 - 1 := by
  simp [COPY_LEN_MASK]

@[simp, scalar_tac_simps, agrind =, grind =, bvify]
theorem shared.command.DIST_CODE_MASK_val : DIST_CODE_MASK.val = 2 ^ 10 - 1 := by
  simp [DIST_CODE_MASK]

/-- The seven bits a copy length delta occupies in `copy_len`, in two's
complement. -/
def deltaField (d : Int) : Nat := (d % 128).toNat

/-- `copy_len_code` widens the seven-bit field by copying its sign bit into bit
seven and reading the byte as `i8`; that gives back every delta from -64 to 63. -/
theorem deltaField_decode : ∀ k : Nat, k < 128 →
    Int.bmod ((deltaField ((k : Int) - 64) ||| (deltaField ((k : Int) - 64) &&& 64) * 2 : Nat) : Int)
      (2 ^ 8) = (k : Int) - 64 := by
  decide +kernel

/-- `Command::new` stores the delta as `delta as i8 as u8 as u32` shifted to bit
25 of a `u32`, which keeps exactly its seven-bit field. -/
theorem deltaField_encode : ∀ k : Nat, k < 128 →
    ((((k : Int) - 64) % 2 ^ 8).toNat * 2 ^ 25) % 2 ^ 32 = deltaField ((k : Int) - 64) * 2 ^ 25 := by
  decide +kernel

theorem deltaField_lt (d : Int) : deltaField d < 128 := by
  simp only [deltaField]; have := Int.emod_nonneg d (by decide : (128 : Int) ≠ 0)
  have := Int.emod_lt_of_pos d (by decide : (0 : Int) < 128); agrind

/-- Every delta in range is `k - 64` for some `k < 128`. -/
theorem delta_as_offset (d : Int) (h1 : -64 ≤ d) (h2 : d ≤ 63) :
    ∃ k : Nat, k < 128 ∧ d = (k : Int) - 64 :=
  ⟨(d + 64).toNat, by agrind, by agrind⟩

attribute [local simp, local scalar_tac_simps] Nat.shiftRight_eq_div_pow

/-- **Spec theorem for `mbrotli::shared::command::Command::copy_len_code`**
A command whose `copy_len` holds the copy length `L` in bits 0..24 and the
delta `d` in bits 25..31 reconstructs `L + d`, the length its symbol encodes. -/
@[step]
theorem Command.copy_len_code.spec (self : Command) (L : Nat) (d : Int)
    (hL : L < 2 ^ 25) (hd1 : -64 ≤ d) (hd2 : d ≤ 63) (hpos : 0 ≤ (L : Int) + d)
    (hcl : self.copy_len.val = L + deltaField d * 2 ^ 25) :
    self.copy_len_code ⦃ (r : U32) => (r.val : Int) = L + d ⦄ := by
  have := numBits_ge
  have hf := deltaField_lt d
  obtain ⟨k, hk, rfl⟩ := delta_as_offset d hd1 hd2
  unfold Command.copy_len_code
  step as ⟨ modifier, modifier_post ⟩
  have hm : modifier.val = deltaField ((k : Int) - 64) := by
    rw [modifier_post, COPY_LEN_CODE_SHIFT_val, hcl, Nat.shiftRight_eq_div_pow,
      Nat.add_mul_div_right _ _ (Nat.two_pow_pos _), Nat.div_eq_of_lt hL]
    agrind
  step as ⟨ i, i_post ⟩
  step as ⟨ i1, i1_post ⟩
  step as ⟨ i2, i2_post ⟩
  have hi2 : i2.val = deltaField ((k : Int) - 64) ||| (deltaField ((k : Int) - 64) &&& 64) * 2 := by
    rw [i2_post, UScalar.val_or, i1_post, i_post, UScalar.val_and, hm]
    have : deltaField ((k : Int) - 64) &&& 64 ≤ 64 := Nat.and_le_right
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by scalar_tac)]
    rfl
  have hi2lt : i2.val < 256 := by
    have : ∀ m < 128, (m ||| (m &&& 64) * 2) < 256 := by decide
    rw [hi2]; exact this _ hf
  step as ⟨ i3, i3_post ⟩
  step as ⟨ i4, i4_post ⟩
  step as ⟨ delta, delta_post ⟩
  have hdelta : delta.val = (k : Int) - 64 := by
    rw [delta_post, IScalar.cast_val_eq, i4_post, UScalar.hcast_val_eq, i3_post, UScalar.cast_val_eq,
      Nat.mod_eq_of_lt (by scalar_tac), hi2]
    rw [show IScalarTy.I8.numBits = 8 from rfl, show IScalarTy.I32.numBits = 32 from rfl,
      show min 32 8 = 8 from rfl, Int.bmod_bmod]
    exact deltaField_decode k hk
  step as ⟨ i5, i5_post ⟩
  have hi5 : i5.val = L := by
    rw [i5_post, UScalar.val_and, COPY_LEN_MASK_val, hcl, Nat.and_two_pow_sub_one_eq_mod,
      Nat.add_mul_mod_self_right, Nat.mod_eq_of_lt hL]
  step as ⟨ i6, i6_post ⟩
  have hi6 : i6.val = L := by
    rw [i6_post, UScalar.hcast_val_eq, hi5, show IScalarTy.I32.numBits = 32 from rfl]
    exact Int.bmod_eq_of_le (by agrind) (by agrind)
  step as ⟨ i7, i7_post ⟩
  rw [IScalar.hcast_val_eq, i7_post, hi6, hdelta, show UScalarTy.U32.numBits = 32 from rfl,
    Int.emod_eq_of_lt (by agrind) (by agrind), Int.toNat_of_nonneg (by agrind)]

/-- For every distance code, short, direct or bucketed, the distance symbol in
the low ten bits of the encoder's code is 0 exactly for distance code 0: the
only code that reuses the last distance. -/
theorem prefix_encode_copy_distance.spec_any (distance_code : Usize)
    (num_direct_codes postfix_bits : U32) (hp : postfix_bits.val ≤ 3)
    (hnd : num_direct_codes.val ≤ 120) (hdc : distance_code.val ≤ 2 ^ 31 + 15) :
    prefix_encode_copy_distance distance_code num_direct_codes postfix_bits
      ⦃ (code : U16) (_extra : U32) => (code.val % 1024 = 0 ↔ distance_code.val = 0) ⦄ := by
  by_cases hlt : distance_code.val < 16 + num_direct_codes.val
  · apply WP.spec_mono (shared.command.prefix_encode_copy_distance.spec_direct _ _ _ hnd hlt)
    rintro ⟨code, _extra⟩ ⟨hcode, -⟩
    simp only [WP.uncurry'_pair] at *
    rw [hcode, Nat.mod_eq_of_lt (by agrind)]
  · have hP32 : 2 ^ 32 ≤ 2 ^ (30 + postfix_bits.val + 2) := Nat.pow_le_pow_right (by decide) (by agrind)
    have hP5 : 2 ^ (postfix_bits.val + 2) ≤ 2 ^ 5 := Nat.pow_le_pow_right (by decide) (by agrind)
    have hdlt : Mbrotli.Model.dist postfix_bits.val num_direct_codes.val distance_code.val <
        2 ^ (30 + postfix_bits.val + 2) := by
      simp only [Mbrotli.Model.dist]; agrind
    obtain ⟨h16, -⟩ := emitted_fields postfix_bits.val num_direct_codes.val distance_code.val 30 hp hnd
      (by agrind) hdlt le_rfl
    apply WP.spec_mono (shared.command.prefix_encode_copy_distance.spec _ _ _ hp hnd (by agrind) hdc)
    rintro ⟨code, _extra⟩ ⟨hcode, -⟩
    simp only [WP.uncurry'_pair] at *
    rw [hcode]
    constructor
    · intro h; agrind
    · intro h; agrind

/-- What `Command::new` guarantees about the lengths it stores: the insert
length, the copy length and its delta in `copy_len`, and an insert-and-copy
length symbol whose RFC codes hold the insert length and the length the decoder
reconstructs, implicit only when the distance code is 0. -/
def Command.Lengths (c : Command) (insertlen copylen : Nat) (delta : Int) (implicitOk : Bool) : Prop :=
  c.insert_len.val = insertlen ∧
  c.copy_len.val = copylen + deltaField delta * 2 ^ 25 ∧
  c.cmd_prefix.val < commandSymbols ∧
  InsertCodeOf insertlen (insertCode c.cmd_prefix.val) ∧
  CopyCodeOf (copylen + delta).toNat (copyCode c.cmd_prefix.val) ∧
  implicitDistance c.cmd_prefix.val = (implicitOk && decide (insertCode c.cmd_prefix.val < 8) &&
    decide (copyCode c.cmd_prefix.val < 16))

/-- **Spec theorem for `mbrotli::shared::command::Command::new`**
For every insert length and copy length the format can carry, every delta from
-64 to 63 and every distance code below `2^31 + 16`, the command stores the
lengths and the symbol of `Command.Lengths`. The symbol reuses the last
distance only for distance code 0, as RFC 7932 section 5 requires. -/
@[step]
theorem Command.new.spec (dist : shared.distance.DistanceParams) (insertlen copylen : Usize)
    (copylen_code_delta : I32) (distance_code : Usize)
    (hp : dist.postfix_bits.val ≤ 3) (hnd : dist.num_direct.val ≤ 120)
    (hi : insertlen.val ≤ 16799809) (hc : copylen.val < 2 ^ 25)
    (hd1 : -64 ≤ copylen_code_delta.val) (hd2 : copylen_code_delta.val ≤ 63)
    (hcl2 : 2 ≤ (copylen.val : Int) + copylen_code_delta.val)
    (hcl : (copylen.val : Int) + copylen_code_delta.val ≤ 16779333)
    (hdc : distance_code.val ≤ 2 ^ 31 + 15) :
    Command.new dist insertlen copylen copylen_code_delta distance_code ⦃ (c : Command) =>
      Command.Lengths c insertlen.val copylen.val copylen_code_delta.val
        (decide (distance_code.val = 0)) ⦄ := by
  have := numBits_ge
  obtain ⟨k, hk, hkd⟩ := delta_as_offset _ hd1 hd2
  unfold Command.new
  step as ⟨ i, i_post ⟩
  step as ⟨ i1, i1_post ⟩
  step as ⟨ delta, delta_post ⟩
  step with prefix_encode_copy_distance.spec_any as ⟨ dist_prefix, dist_extra, hzero ⟩
  have hd : copylen_code_delta.val = (k : Int) - 64 := hkd
  step as ⟨ i2, i2_post ⟩
  step as ⟨ i3, i3_post ⟩
  have hi2 : i2.val = copylen.val := by
    rw [i2_post, UScalar.hcast_val_eq, show IScalarTy.I64.numBits = 64 from rfl]
    exact Int.bmod_eq_of_le (by agrind) (by agrind)
  have hi3 : i3.val = copylen_code_delta.val := by
    rw [i3_post, IScalar.cast_val_eq, show IScalarTy.I64.numBits = 64 from rfl,
      show IScalarTy.I32.numBits = 32 from rfl, show min 64 32 = 32 from rfl]
    exact Int.bmod_eq_of_le (by agrind) (by agrind)
  step as ⟨ i4, i4_post ⟩
  step as ⟨ i5, i5_post ⟩
  have hi5 : (i5.val : Int) = copylen.val + copylen_code_delta.val := by
    rw [i5_post, IScalar.hcast_val_eq, i4_post, hi2, hi3, UScalarTy.Usize_numBits_eq]
    have : (2 : Int) ^ 32 ≤ 2 ^ System.Platform.numBits := pow_le_pow_right₀ (by decide) numBits_ge
    rw [Int.emod_eq_of_lt (by agrind) (by agrind), Int.toNat_of_nonneg (by agrind)]
  step as ⟨ i6, i6_post ⟩
  have hi6 : (i6 = 0#u16) ↔ distance_code.val = 0 := by
    rw [← hzero]
    have : i6.val = dist_prefix.val % 1024 := by
      rw [i6_post, UScalar.val_and, DIST_CODE_MASK_val, Nat.and_two_pow_sub_one_eq_mod]
    constructor
    · intro h; rw [← this, h]; rfl
    · intro h; exact UScalar.eq_of_val_eq (by rw [this]; exact h)
  step with length_code.spec as ⟨ cmd_prefix, hlt, hins, hcp, himp ⟩
  step as ⟨ i7, i7_post ⟩
  step as ⟨ i8, i8_post ⟩
  step as ⟨ i9, i9_post ⟩
  step as ⟨ i10, i10_post ⟩
  have hmod8 : (copylen_code_delta.val % 2 ^ 8).toNat < 2 ^ 8 := by
    have := Int.emod_lt_of_pos copylen_code_delta.val (by decide : (0 : Int) < 2 ^ 8)
    have := Int.emod_nonneg copylen_code_delta.val (by decide : (2 : Int) ^ 8 ≠ 0)
    agrind
  have hdel : delta.val = ((copylen_code_delta.val) % 2 ^ 8).toNat := by
    rw [delta_post, UScalar.cast_val_eq, i1_post, IScalar.hcast_val_eq, i_post, IScalar.cast_val_eq,
      show IScalarTy.I8.numBits = 8 from rfl, show IScalarTy.I32.numBits = 32 from rfl,
      show min 8 32 = 8 from rfl, show UScalarTy.U8.numBits = 8 from rfl,
      Int.bmod_eq_of_le (by agrind) (by agrind)]
    exact Nat.mod_eq_of_lt (lt_of_lt_of_le hmod8 (by decide))
  have hi9 : i9.val = deltaField copylen_code_delta.val * 2 ^ 25 := by
    rw [i9_post, COPY_LEN_CODE_SHIFT_val, Nat.shiftLeft_eq, hdel, hd,
      show U32.size = 2 ^ 32 by simp [U32.size, U32.numBits]]
    exact deltaField_encode k hk
  have hi10 : i10.val = copylen.val + deltaField copylen_code_delta.val * 2 ^ 25 := by
    rw [i10_post, UScalar.val_or, i8_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac), hi9,
      Nat.lor_comm, ← Nat.shiftLeft_eq, ← Nat.shiftLeft_add_eq_or_of_lt hc, Nat.shiftLeft_eq]
    agrind
  have hi7 : i7.val = insertlen.val := by
    rw [i7_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
  have hcopy : i5.val = (copylen.val + copylen_code_delta.val : Int).toNat := by agrind
  rw [hcopy] at hcp
  have himp' : decide (i6 = 0#u16) = decide (distance_code.val = 0) := by
    simp only [hi6]
  rw [himp'] at himp
  exact ⟨hi7, hi10, hlt, hins, hcp, himp⟩

/-- `u64::from(u32)` keeps the value. -/
@[local step]
theorem from_u64_u32.spec (x : U32) :
    lift (core.convert.num.FromU64U32.from x) ⦃ (y : U64) => y.val = x.val ⦄ := by
  simp only [lift, WP.spec_ok, core.convert.num.FromU64U32.from_val_eq]

/-- **Spec theorem for `mbrotli::shared::command::Command::extra_bits`**
For a command whose insert length and reconstructed copy length `K` the format
can carry, the extra bits are the insert field, `insertlen` minus the first
length of its code, in the low `INS_EXTRA` bits and the copy field, `K` minus the
first length of its code, above them: the order in which RFC 7932 section 5
writes them, insert extra bits first. -/
@[step]
theorem Command.extra_bits.spec (self : Command) (L : Nat) (d : Int)
    (hL : L < 2 ^ 25) (hd1 : -64 ≤ d) (hd2 : d ≤ 63)
    (hK2 : 2 ≤ (L : Int) + d) (hK : (L : Int) + d ≤ 16779333)
    (hcl : self.copy_len.val = L + deltaField d * 2 ^ 25) (hins : self.insert_len.val ≤ 16799809) :
    self.extra_bits ⦃ (n : U32) (bits : U64) =>
      ∃ ic cc, InsertCodeOf self.insert_len.val ic ∧ CopyCodeOf ((L : Int) + d).toNat cc ∧
        n.val = (row insertRows ic).extra + (row copyRows cc).extra ∧
        bits.val = (((L : Int) + d).toNat - (row copyRows cc).lo) * 2 ^ (row insertRows ic).extra +
          (self.insert_len.val - (row insertRows ic).lo) ⦄ := by
  have := numBits_ge
  unfold Command.extra_bits
  step with Command.copy_len_code.spec self L d hL hd1 hd2 (by agrind) hcl as ⟨ copylen_code, hcode ⟩
  have hK' : copylen_code.val = ((L : Int) + d).toNat := by agrind
  step as ⟨ i, i_post ⟩
  have hi : i.val = self.insert_len.val := by
    rw [i_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (lt_usize_pow _ (by scalar_tac))]
  step as ⟨ inscode, hic24, hilo, hihi ⟩
  step as ⟨ i1, i1_post ⟩
  have hi1 : i1.val = ((L : Int) + d).toNat := by
    rw [i1_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (lt_usize_pow _ (by scalar_tac)), hK']
  step as ⟨ copycode, hcc ⟩
  rw [hi1] at hcc
  rw [hi] at hilo hihi
  obtain ⟨hcc24, hclo, hchi⟩ := hcc
  have hext : ∀ c < 24, (row insertRows c).extra ≤ 24 ∧ (row copyRows c).extra ≤ 24 := by decide
  have hcu : ∀ x : U16, (UScalar.cast .Usize x).val = x.val := fun x => by
    rw [UScalar.cast_val_eq]; exact Nat.mod_eq_of_lt (lt_usize_pow _ (by scalar_tac))
  step as ⟨ i2, i2_post ⟩
  have hi2 : i2.val = inscode.val := by rw [i2_post, hcu]
  step as ⟨ insnumextra, insnumextra_post ⟩
  step as ⟨ i3, i3_post ⟩
  have hi3 : i3.val = inscode.val := by rw [i3_post, hcu]
  step as ⟨ i4, i4_post ⟩
  step as ⟨ i5, i5_post ⟩
  step as ⟨ insextraval, insextraval_post ⟩
  step as ⟨ i6, i6_post ⟩
  have hi6 : i6.val = copycode.val := by rw [i6_post, hcu]
  step as ⟨ i7, i7_post ⟩
  step as ⟨ i8, i8_post ⟩
  step as ⟨ copyextraval, copyextraval_post ⟩
  step as ⟨ i9, i9_post ⟩
  have hi9 : i9.val = copycode.val := by rw [i9_post, hcu]
  step as ⟨ i10, i10_post ⟩
  rw [hi2] at insnumextra_post
  rw [hi9] at i10_post
  have := hext _ hic24
  have := hext _ hcc24
  step as ⟨ i11, i11_post ⟩
  step as ⟨ i12, i12_post ⟩
  step as ⟨ i13, i13_post ⟩
  have wi : ∀ c < 24, (row insertRows c).hi + 1 = (row insertRows c).lo + 2 ^ (row insertRows c).extra := by
    decide
  have wc : ∀ c < 24, (row copyRows c).hi + 1 = (row copyRows c).lo + 2 ^ (row copyRows c).extra := by
    decide
  have hwi := wi _ hic24
  have hwc := wc _ hcc24
  rw [hi3] at i4_post
  rw [hi6] at i7_post
  have hins_f : insextraval.val = self.insert_len.val - (row insertRows inscode.val).lo := by
    rw [insextraval_post, i5_post, i4_post]
  have hcopy_f : copyextraval.val = ((L : Int) + d).toNat - (row copyRows copycode.val).lo := by
    rw [copyextraval_post, i8_post, i7_post, hK']
  have hinsw : insextraval.val < 2 ^ insnumextra.val := by rw [hins_f, insnumextra_post]; agrind
  have hcopyw : copyextraval.val < 2 ^ 24 := by
    have : 2 ^ (row copyRows copycode.val).extra ≤ 2 ^ 24 := Nat.pow_le_pow_right (by decide) (by agrind)
    rw [hcopy_f]; agrind
  have hpe : 2 ^ insnumextra.val ≤ 2 ^ 24 := Nat.pow_le_pow_right (by decide) (by agrind)
  have hi12 : i12.val = copyextraval.val * 2 ^ insnumextra.val := by
    rw [i12_post, Nat.shiftLeft_eq, show U64.size = 2 ^ 64 by simp [U64.size, U64.numBits]]
    apply Nat.mod_eq_of_lt
    calc copyextraval.val * 2 ^ insnumextra.val < 2 ^ 24 * 2 ^ 24 :=
          Nat.mul_lt_mul_of_lt_of_le hcopyw hpe (Nat.two_pow_pos _)
      _ ≤ 2 ^ 64 := by norm_num
  refine ⟨inscode.val, copycode.val, ⟨hic24, hilo, hihi⟩, ⟨hcc24, hclo, hchi⟩, ?_, ?_⟩
  · rw [i11_post, insnumextra_post, i10_post]
  · rw [i13_post, UScalar.val_or, hi12, ← Nat.shiftLeft_eq,
      ← Nat.shiftLeft_add_eq_or_of_lt hinsw, Nat.shiftLeft_eq, hins_f, hcopy_f, insnumextra_post]

/-- What `Command::distance_context` computes from the symbol: the copy code's
low bits in the four cell rows whose copy codes start at 0, otherwise 3. -/
def encoderContext (s : Nat) : Nat :=
  if (s / 64 = 0 ∨ s / 64 = 2 ∨ s / 64 = 4 ∨ s / 64 = 7) ∧ s % 8 ≤ 2 then s % 8 else 3

/-- Reading the context off the symbol agrees with reading it off the copy
code's first length, for every symbol. -/
theorem encoderContext_code : ∀ s < commandSymbols,
    encoderContext s = if (row copyRows (copyCode s)).lo > 4 then 3 else (row copyRows (copyCode s)).lo - 2 := by
  decide +kernel

/-- **Spec theorem for `mbrotli::shared::command::Command::distance_context`**
The section 7.2 context of every copy length the command's symbol can carry. -/
@[step]
theorem Command.distance_context.spec (self : Command) :
    self.distance_context ⦃ (r : Usize) => r.val = encoderContext self.cmd_prefix.val ⦄ := by
  have := numBits_ge
  unfold Command.distance_context
  step as ⟨ r, r_post ⟩
  step as ⟨ c, c_post ⟩
  have hr : r.val = self.cmd_prefix.val / 64 := by rw [r_post, Nat.shiftRight_eq_div_pow]
  have hc : c.val = self.cmd_prefix.val % 8 := by
    rw [c_post, UScalar.val_and]; exact Nat.and_two_pow_sub_one_eq_mod _ 3
  have hcast : (UScalar.cast .Usize c).val = c.val := by
    rw [UScalar.cast_val_eq]; exact Nat.mod_eq_of_lt (lt_usize_pow _ (by scalar_tac))
  simp only [encoderContext]
  split
  · split
    · simp only [WP.spec_ok, hcast]
      split
      · agrind
      · agrind
    · simp only [WP.spec_ok]
      split
      · agrind
      · agrind
  · split
    · split
      · simp only [WP.spec_ok, hcast]
        split
        · agrind
        · agrind
      · simp only [WP.spec_ok]
        split
        · agrind
        · agrind
    · split
      · split
        · simp only [WP.spec_ok, hcast]
          split
          · agrind
          · agrind
        · simp only [WP.spec_ok]
          split
          · agrind
          · agrind
      · split
        · split
          · simp only [WP.spec_ok, hcast]
            split
            · agrind
            · agrind
          · simp only [WP.spec_ok]
            split
            · agrind
            · agrind
        · simp only [WP.spec_ok]
          split
          · agrind
          · agrind

/-- **Spec theorem for `mbrotli::shared::command::Command::has_distance`**
A command that copies writes a distance symbol exactly when its symbol does
not reuse the last distance (RFC 7932, section 5). -/
@[step]
theorem Command.has_distance.spec (self : Command) :
    self.has_distance ⦃ (b : Bool) =>
      b = (decide (self.copy_len.val % 2 ^ 25 ≠ 0) && !implicitDistance self.cmd_prefix.val) ⦄ := by
  unfold Command.has_distance Command.impl.copy_len
  have hlen : (self.copy_len &&& COPY_LEN_MASK).val = self.copy_len.val % 2 ^ 25 := by
    rw [UScalar.val_and, COPY_LEN_MASK_val, Nat.and_two_pow_sub_one_eq_mod]
  simp only [Std.bind_ok]
  split
  · rename_i h
    have h' : self.copy_len.val % 2 ^ 25 ≠ 0 := by
      intro hz; simp only [bne_iff_ne, ne_eq] at h; apply h
      exact UScalar.eq_of_val_eq (by rw [hlen, hz]; rfl)
    simp only [WP.spec_ok, implicitDistance]
    agrind
  · rename_i h
    have h' : self.copy_len.val % 2 ^ 25 = 0 := by rw [← hlen]; agrind
    simp only [WP.spec_ok, h']
    agrind

/-- **Spec theorem for `mbrotli::shared::command::Command::insert_only`**
The meta-block's trailing literals: a symbol whose insert code holds the length
and whose copy code is that of length 4, which never reuses the last distance,
stored with no copy so that no distance symbol follows. -/
@[step]
theorem Command.insert_only.spec (insertlen : Usize) (hi : insertlen.val ≤ 16799809) :
    Command.insert_only insertlen ⦃ (c : Command) =>
      Command.Lengths c insertlen.val 0 4 false ⦄ := by
  have := numBits_ge
  unfold Command.insert_only
  step as ⟨ i, i_post ⟩
  step as ⟨ i1, i1_post ⟩
  step with length_code.spec as ⟨ s, hlt, hins, hcp, himp ⟩
  step as ⟨ i3, i3_post ⟩
  refine ⟨?_, ?_, hlt, hins, hcp, himp⟩
  · show i.val = _
    rw [i_post, UScalar.cast_val_eq, Nat.mod_eq_of_lt (by scalar_tac)]
  · show i1.val = _
    rw [i1_post, COPY_LEN_CODE_SHIFT_val, show U32.size = 2 ^ 32 by simp [U32.size, U32.numBits]]
    decide

/-- **Commands round-trip.** For every command the encoder builds, the decoder's
command table entry for its symbol reads both lengths back out of the command's
extra bits: the low `insert_extra` bits added to `insert_base` give the insert
length, the bits above them added to `copy_base` give the copy length the
decoder reconstructs. The entry reuses the last distance only for distance
code 0, and its distance context is the one the encoder codes the distance in. -/
theorem command_round_trip (dist : shared.distance.DistanceParams) (insertlen copylen : Usize)
    (copylen_code_delta : I32) (distance_code : Usize)
    (hp : dist.postfix_bits.val ≤ 3) (hnd : dist.num_direct.val ≤ 120)
    (hi : insertlen.val ≤ 16799809) (hc : copylen.val < 2 ^ 25)
    (hd1 : -64 ≤ copylen_code_delta.val) (hd2 : copylen_code_delta.val ≤ 63)
    (hcl2 : 2 ≤ (copylen.val : Int) + copylen_code_delta.val)
    (hcl : (copylen.val : Int) + copylen_code_delta.val ≤ 16779333)
    (hdc : distance_code.val ≤ 2 ^ 31 + 15) :
    Command.new dist insertlen copylen copylen_code_delta distance_code ⦃ (c : Command) =>
      (c.extra_bits ⦃ (n : U32) (bits : U64) =>
        decompressor.core.stream.commands ⦃ (t : Array decompressor.core.stream.Command 1024#usize) =>
          n.val = t[c.cmd_prefix.val]!.insert_extra.val + t[c.cmd_prefix.val]!.copy_extra.val ∧
          bits.val < 2 ^ n.val ∧
          t[c.cmd_prefix.val]!.insert_base.val + bits.val % 2 ^ t[c.cmd_prefix.val]!.insert_extra.val =
            insertlen.val ∧
          ((t[c.cmd_prefix.val]!.copy_base.val + bits.val / 2 ^ t[c.cmd_prefix.val]!.insert_extra.val :
            Nat) : Int) = copylen.val + copylen_code_delta.val ∧
          (t[c.cmd_prefix.val]!.implicit = true → distance_code.val = 0) ∧
          t[c.cmd_prefix.val]!.distance_context.val =
            distanceContext ((copylen.val : Int) + copylen_code_delta.val).toNat ⦄ ⦄) ∧
      c.distance_context ⦃ (ctx : Usize) =>
        ctx.val = distanceContext ((copylen.val : Int) + copylen_code_delta.val).toNat ⦄ ⦄ := by
  apply WP.spec_mono (Command.new.spec dist insertlen copylen copylen_code_delta distance_code hp hnd
    hi hc hd1 hd2 hcl2 hcl hdc)
  rintro c ⟨hlen, hcpl, hs, hic, hcc, himp⟩
  set K := ((copylen.val : Int) + copylen_code_delta.val).toNat with hK
  refine ⟨?_, ?_⟩
  · apply WP.spec_mono (Command.extra_bits.spec c copylen.val copylen_code_delta.val hc hd1 hd2 hcl2 hcl
      hcpl (by rw [hlen]; exact hi))
    rintro ⟨n, bits⟩ ⟨ic, cc, hic', hcc', hn, hbits⟩
    rw [hlen] at hic' hbits
    rw [← hK] at hcc' hbits
    have hie := insert_code_unique _ _ _ hic' hic
    have hce := copy_code_unique _ _ _ hcc' hcc
    subst hie hce
    apply WP.spec_mono mbrotli.commands.spec
    intro t ht
    obtain ⟨hib, hiex, hcb, hcex, -, himpl, hctx⟩ := ht c.cmd_prefix.val hs
    obtain ⟨hic24, hilo, hihi⟩ := hic
    obtain ⟨hcc24, hclo, hchi⟩ := hcc
    have wi : ∀ c < 24, (row insertRows c).hi + 1 = (row insertRows c).lo + 2 ^ (row insertRows c).extra := by
      decide
    have wc : ∀ c < 24, (row copyRows c).hi + 1 = (row copyRows c).lo + 2 ^ (row copyRows c).extra := by
      decide
    have hwi := wi _ hic24
    have hwc := wc _ hcc24
    have hP : 0 < 2 ^ (row insertRows (insertCode c.cmd_prefix.val)).extra := Nat.two_pow_pos _
    have hlow : insertlen.val - (row insertRows (insertCode c.cmd_prefix.val)).lo <
        2 ^ (row insertRows (insertCode c.cmd_prefix.val)).extra := by agrind
    have hhigh : K - (row copyRows (copyCode c.cmd_prefix.val)).lo <
        2 ^ (row copyRows (copyCode c.cmd_prefix.val)).extra := by agrind
    have hmod : bits.val % 2 ^ (row insertRows (insertCode c.cmd_prefix.val)).extra =
        insertlen.val - (row insertRows (insertCode c.cmd_prefix.val)).lo := by
      rw [hbits, Nat.mul_comm, Nat.mul_add_mod, Nat.mod_eq_of_lt hlow]
    have hdiv : bits.val / 2 ^ (row insertRows (insertCode c.cmd_prefix.val)).extra =
        K - (row copyRows (copyCode c.cmd_prefix.val)).lo := by
      rw [hbits, Nat.mul_comm, Nat.mul_add_div hP, Nat.div_eq_of_lt hlow]; rfl
    rw [hiex, hcex, hib, hcb, hmod, hdiv, himpl, hctx K hclo hchi, ← hn]
    refine ⟨rfl, ?_, by agrind, ?_, ?_, rfl⟩
    · rw [hn, hbits, Nat.pow_add]
      calc (K - (row copyRows (copyCode c.cmd_prefix.val)).lo) *
            2 ^ (row insertRows (insertCode c.cmd_prefix.val)).extra +
            (insertlen.val - (row insertRows (insertCode c.cmd_prefix.val)).lo)
          < (K - (row copyRows (copyCode c.cmd_prefix.val)).lo) *
            2 ^ (row insertRows (insertCode c.cmd_prefix.val)).extra +
            2 ^ (row insertRows (insertCode c.cmd_prefix.val)).extra := Nat.add_lt_add_left hlow _
        _ = (K - (row copyRows (copyCode c.cmd_prefix.val)).lo + 1) *
            2 ^ (row insertRows (insertCode c.cmd_prefix.val)).extra := by ring
        _ ≤ 2 ^ (row insertRows (insertCode c.cmd_prefix.val)).extra *
            2 ^ (row copyRows (copyCode c.cmd_prefix.val)).extra := by
          rw [Nat.mul_comm]; exact Nat.mul_le_mul_left _ hhigh
    · have : (row copyRows (copyCode c.cmd_prefix.val)).lo + (K - (row copyRows (copyCode c.cmd_prefix.val)).lo) = K := by
        agrind
      rw [this, hK, Int.toNat_of_nonneg (by agrind)]
    · intro h
      rw [himp] at h
      simp only [Bool.and_eq_true, decide_eq_true_eq] at h
      exact h.1.1
  · apply WP.spec_mono (Command.distance_context.spec c)
    intro ctx hctx
    rw [hctx, encoderContext_code _ hs, ← distanceContext_of_code _ K hcc.1 hcc.2.1 hcc.2.2]

end mbrotli
