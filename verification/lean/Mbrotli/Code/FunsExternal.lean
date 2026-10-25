module

public import Aeneas
public import Mbrotli.Code.Types

/-! # Models of the standard-library items the translation calls

Aeneas translates calls into the Rust standard library to Lean definitions from
its own library; these four have no model there yet, so they are written here,
following the behaviour the standard library documents. They are part of the
trusted base: each restates one documented function and is short enough to read
against its documentation.

`scripts/extract_lean.py` lists the same four names in `EXTERNALS` and fails
when the translation needs any other unmodelled item.
-/

@[expose] public section

open Aeneas Aeneas.Std Result

/-- `<u64 as TryFrom<u128>>::try_from`: the value when it fits in 64 bits,
`TryFromIntError` otherwise. -/
@[rust_fun
  "core::convert::num::{core::convert::TryFrom<u64, u128, core::num::error::TryFromIntError>}::try_from"]
def U64.Insts.CoreConvertTryFromU128TryFromIntError.try_from (x : Std.U128) :
    Result (core.result.Result Std.U64 core.num.error.TryFromIntError) :=
  core.num.tryFromUScalar .U64 x

/-- `u64::checked_add_signed`: the sum when it lies in `0..=u64::MAX`, `None`
otherwise. -/
@[rust_fun "core::num::{u64}::checked_add_signed"]
def core.num.U64.checked_add_signed (x : Std.U64) (y : Std.I64) : Result (Option Std.U64) :=
  if 0 ≤ (x.val : Int) + y.val ∧ (x.val : Int) + y.val ≤ U64.max then
    ok (some ⟨BitVec.ofNat 64 ((x.val : Int) + y.val).toNat⟩)
  else
    ok none

/-- `Option::ok_or_else`: `Ok` of the payload, or `Err` of what the closure
returns when there is none. -/
@[rust_fun "core::option::{core::option::Option<@T>}::ok_or_else"]
def core.option.Option.ok_or_else {T : Type _} {E : Type _} {F : Type _}
    (fnOnce : core.ops.function.FnOnce F Unit E) (x : Option T) (f : F) :
    Result (core.result.Result T E) :=
  match x with
  | some value => ok (.Ok value)
  | none => do
      let e ← fnOnce.call_once f ()
      ok (.Err e)

/-- `Option::filter`: keeps the payload when the predicate holds for it. -/
@[rust_fun "core::option::{core::option::Option<@T>}::filter"]
def core.option.Option.filter {T : Type _} {P : Type _}
    (fnOnce : core.ops.function.FnOnce P T Bool) (x : Option T) (p : P) : Result (Option T) :=
  match x with
  | none => ok none
  | some value => do
      let keep ← fnOnce.call_once p value
      ok (if keep then some value else none)

end
