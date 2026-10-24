# libFuzzer targets

This package runs the AFL targets' bodies under libFuzzer, which is what
[ClusterFuzzLite](https://google.github.io/clusterfuzzlite/) builds for Rust.
It owns no target logic: each file in `fuzz_targets/` is a three line
`fuzz_target!` adapter around the body the AFL binary of the same name runs,
from the `mbrotli-afl` library. Inputs, oracles and corpora are described in the
[AFL guide](../afl/README.md).

Like `fuzz/afl`, the package is excluded from the root workspace.

## Targets

The 19 stable targets are every stable AFL target except the fixed-quality
`q*_roundtrip` ones, whose qualities `params_roundtrip` and `differential_c`
already reach. `--features experimental` adds `decode_serialized`,
`framed_decode`, `framed_encode`, `framed_roundtrip`, `framing` and
`serialized_dictionary`.

## Local runs

cargo-fuzz needs nightly Rust for the sanitizer flags. From the repository root:

```sh
cargo install cargo-fuzz --locked
cargo +nightly fuzz build -O --debug-assertions --fuzz-dir fuzz/libfuzzer
cargo +nightly fuzz run --fuzz-dir fuzz/libfuzzer -O --debug-assertions decompress
```

To reproduce exactly what ClusterFuzzLite builds, including the seed corpora,
run `.clusterfuzzlite/build.sh` with `SRC`, `OUT` and `WORK` set. `SRC` must
contain the repository as `mbrotli`.

## Findings

ClusterFuzzLite attaches the crashing input to the failed workflow run.
Reproduce it with the binary of that target:

```sh
cargo +nightly fuzz run --fuzz-dir fuzz/libfuzzer -O --debug-assertions <target> <crash-file>
```

Then minimize it, commit it under `fuzz/afl/regressions/<target>/`, check that
`cargo afl test` fails on it, and fix the bug. The regression replay does not
need a libFuzzer build.
