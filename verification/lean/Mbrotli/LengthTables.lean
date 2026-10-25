import Mbrotli.Basic
import Mbrotli.Rfc

/-! # The length code tables are the RFC's

`INS_BASE`, `INS_EXTRA`, `COPY_BASE` and `COPY_EXTRA` in `shared/format.rs`, and
the decoder's `CELLS`, hold exactly the values RFC 7932 section 5 prints. Each
fact is also stated as a `step` specification of indexing the array, which is
how the code reads it.
-/

open Aeneas Aeneas.Std Result
open Mbrotli.Rfc

namespace mbrotli

theorem shared.format.INS_BASE_val :
    ∀ i < 24, (shared.format.INS_BASE.val[i]!).val = (row insertRows i).lo := by
  rw [shared.format.INS_BASE]
  decide +kernel

/-- `INS_BASE[i]` is the first length of insert code `i` (RFC 7932, section 5). -/
@[step]
theorem shared.format.INS_BASE.spec (i : Usize) (h : i.val < 24) :
    Array.index_usize shared.format.INS_BASE i ⦃ (x : U32) => x.val = (row insertRows i.val).lo ⦄ := by
  step as ⟨ x, x_post ⟩
  rw [x_post, List.Inhabited_getElem_eq_getElem!]
  · exact shared.format.INS_BASE_val _ h
  · scalar_tac

theorem shared.format.INS_EXTRA_val :
    ∀ i < 24, (shared.format.INS_EXTRA.val[i]!).val = (row insertRows i).extra := by
  rw [shared.format.INS_EXTRA]
  decide +kernel

/-- `INS_EXTRA[i]` is the extra-bit count of insert code `i`. -/
@[step]
theorem shared.format.INS_EXTRA.spec (i : Usize) (h : i.val < 24) :
    Array.index_usize shared.format.INS_EXTRA i ⦃ (x : U32) => x.val = (row insertRows i.val).extra ⦄ := by
  step as ⟨ x, x_post ⟩
  rw [x_post, List.Inhabited_getElem_eq_getElem!]
  · exact shared.format.INS_EXTRA_val _ h
  · scalar_tac

theorem shared.format.COPY_BASE_val :
    ∀ i < 24, (shared.format.COPY_BASE.val[i]!).val = (row copyRows i).lo := by
  rw [shared.format.COPY_BASE]
  decide +kernel

/-- `COPY_BASE[i]` is the first length of copy code `i`. -/
@[step]
theorem shared.format.COPY_BASE.spec (i : Usize) (h : i.val < 24) :
    Array.index_usize shared.format.COPY_BASE i ⦃ (x : U32) => x.val = (row copyRows i.val).lo ⦄ := by
  step as ⟨ x, x_post ⟩
  rw [x_post, List.Inhabited_getElem_eq_getElem!]
  · exact shared.format.COPY_BASE_val _ h
  · scalar_tac

theorem shared.format.COPY_EXTRA_val :
    ∀ i < 24, (shared.format.COPY_EXTRA.val[i]!).val = (row copyRows i).extra := by
  rw [shared.format.COPY_EXTRA]
  decide +kernel

/-- `COPY_EXTRA[i]` is the extra-bit count of copy code `i`. -/
@[step]
theorem shared.format.COPY_EXTRA.spec (i : Usize) (h : i.val < 24) :
    Array.index_usize shared.format.COPY_EXTRA i ⦃ (x : U32) => x.val = (row copyRows i.val).extra ⦄ := by
  step as ⟨ x, x_post ⟩
  rw [x_post, List.Inhabited_getElem_eq_getElem!]
  · exact shared.format.COPY_EXTRA_val _ h
  · scalar_tac

theorem decompressor.core.stream.CELLS_val :
    ∀ i < 11, (decompressor.core.stream.CELLS.val[i]!).val = (cells.getD i (0, 0)).1 + (cells.getD i (0, 0)).2 / 8 := by
  rw [decompressor.core.stream.CELLS]
  decide +kernel

/-- `CELLS[k]` packs the first insert code of block `k`'s cell in bits 3..4 and its first copy code, divided by eight, in bits 0..1. -/
@[step]
theorem decompressor.core.stream.CELLS.spec (i : Usize) (h : i.val < 11) :
    Array.index_usize decompressor.core.stream.CELLS i ⦃ (x : Usize) => x.val = (cells.getD i.val (0, 0)).1 + (cells.getD i.val (0, 0)).2 / 8 ⦄ := by
  step as ⟨ x, x_post ⟩
  rw [x_post, List.Inhabited_getElem_eq_getElem!]
  · exact decompressor.core.stream.CELLS_val _ h
  · scalar_tac

end mbrotli
