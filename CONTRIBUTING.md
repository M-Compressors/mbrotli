# Contributing to mbrotli

Thank you for helping. Bug reports, differential test cases, fuzz findings,
documentation fixes, and code are all welcome. By participating you agree to
follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Security issues are reported privately; see [SECURITY.md](SECURITY.md).

## Before you start

- For anything beyond a small fix, open an issue first so we can agree on the
  approach before you invest time in it.
- Read [`architecture/README.md`](architecture/README.md). It describes how the
  code is organized and is kept current with every change.
- Ordinary encoding is **byte-identical to Google Brotli v1.2.0** (the pinned
  `brotli-ffi/vendor/brotli` revision) at qualities 0–11 and windows 10–24,
  under equivalent streaming settings. Changes to the encoder must keep every
  differential test passing; a heuristic that compresses better but writes
  different bytes will not be merged.
- APIs behind the `experimental` feature (serialized and custom static
  dictionaries, headerless continuations, framing) may change in patch
  releases. The stable API is checked with `cargo-semver-checks` in CI.
- Do not add a dependency on an existing Brotli implementation.
- Do not edit `brotli-ffi/vendor/` unless the change is an upstream vendor
  update.

## Setting up

```sh
git clone --recurse-submodules https://github.com/M-Compressors/mbrotli.git
cd mbrotli
```

If you already cloned without submodules, run
`git submodule update --init --recursive`. The `google-brotli-ffi` crate builds
the vendored C Brotli as the test and benchmark oracle, so a C compiler is
required. The minimum supported Rust version is 1.89.

## Code guidelines

The full rules are in [`AGENTS.md`](AGENTS.md); the essentials:

- **Module shape.** A public module owns the ergonomic API; its private
  `core` submodule owns the implementation. Never expose `core` types, SIMD
  types, FFI details, or low-level errors.
- **Small public APIs.** Prefer borrowed inputs and standard traits (`From`,
  `TryFrom`, `Default`, `Display`, `FromStr`, ...) over inherent constructors.
  Document every public item, with `# Examples`, `# Errors`, `# Panics`, and
  `# Safety` sections where they apply.
- **Errors.** Use `thiserror`. Library code returns `Result`; no `unwrap`,
  `expect`, or panics for recoverable failures. Public errors keep the source
  chain and are `#[non_exhaustive]`.
- **No `unsafe`** in the production code of the `mbrotli` crate.
- **Performance.** Measure before optimizing (the `hotpath` features). SIMD
  goes through `fearless_simd`, keeps a baseline implementation, and selects
  the level outside inner loops; every SIMD level must produce the same output
  as the baseline.
- **Lints.** Fix warnings rather than suppressing them. Do not add
  `#[allow(..)]`; for a demonstrated false positive, use the narrowest
  `#[expect(clippy::lint)]` with a comment explaining why.

## Tests

- Every new or changed function needs tests. The project keeps **100% function
  coverage** of its own Rust code.
- Unit tests sit beside private `core` logic; public API and cross-module
  behavior go in `tests/`; public examples are doc tests.
- Fixing a bug starts with a regression test that fails without the fix.
- Encoder and decoder changes need differential tests against Google's C
  implementation; optimized paths need differential tests against the
  baseline.

## Checks to run before opening a pull request

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
cargo test --workspace --all-features --locked
cargo test --workspace --locked
cargo test --workspace --features experimental --locked
```

All three test runs are needed: `--all-features` turns on `no_std`, which
removes the std-only adapters and parallel APIs. Setting
`CARGO_PROFILE_TEST_OPT_LEVEL=1` makes the compression-heavy suites much faster
while keeping debug assertions and overflow checks.

When you touch Cargo features, also run the feature-isolation checks:

```sh
python3 scripts/check_codec_features.py
python3 scripts/check_decoder_features.py
```

The [development guide](docs/development.md) has the coverage commands
(`cargo llvm-cov` across both feature configurations) and a map of the
repository.

### Fuzzing

The AFL++ targets live in [`fuzz/afl/`](fuzz/afl/README.md), outside the
workspace. After changing anything there, or a public API a fuzz target
calls, run from `fuzz/afl/`:

```sh
cargo fmt --all -- --check
cargo clippy --all-targets --no-default-features -- -D warnings
cargo clippy --all-targets --no-default-features --features experimental -- -D warnings
cargo afl test --no-default-features
cargo afl test --no-default-features --features experimental
```

Turn every minimized crash into a regression input under
`fuzz/afl/regressions/` before fixing it. Never commit AFL findings or output
directories.

### Benchmarks

Performance claims need evidence. Criterion benchmarks compare mbrotli with
Google's C implementation on identical inputs and parameters; see
[`docs/benchmarking.md`](docs/benchmarking.md). Report the command, corpus,
machine, and before/after numbers for both speed and compressed size.

## Documentation and changelog

- Update the specifications and Mermaid diagrams in `architecture/`, and its
  `README.md` index, whenever a change adds, removes, or reshapes a module,
  public API, state machine, data flow, or dispatch boundary. Documentation
  drift counts as an incomplete change.
- Add an entry under "Unreleased" in [`CHANGELOG.md`](CHANGELOG.md) for
  user-visible changes.

## Pull requests

- Keep each pull request focused on one change.
- Fill in the pull request template, including which checks you ran.
- CI runs formatting, Clippy, docs, packaging, feature isolation, `no_std`,
  semver checks, tests on Linux (x86-64 and Arm) and macOS, and the fuzz
  regression corpus. It must pass before merging. Release tags also run
  Miri, sanitizers, fuzz campaigns, and heavy decoder checks; see
  [CI mechanics](architecture/ci.md).

## License

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in this work by you, as defined in the Apache-2.0
license, shall be dual licensed under the MIT and Apache-2.0 licenses, without
any additional terms or conditions.
