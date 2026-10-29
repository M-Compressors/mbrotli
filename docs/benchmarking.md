# Benchmarks and profiling

The independent [implementation comparison](../benchmarks/comparison/Cargo.toml)
measures `mbrotli`, Google C Brotli, Rust `brotli`, `simd-brotli`, and `burli`.
Browse the [benchmark results index](benchmarks/README.md) for one page per
compression quality, with medians across all eight datasets, vertical speed/size
bars, and complete timings. The strongest mbrotli comparisons appear first;
the pages explain the ranking and retain every dataset.
The index also links the recorded run reports, raw data, and limitations.

Both codecs use the same documentation layout under `docs/benchmarks/`:

| Artifact | Encoder | Decoder |
| --- | --- | --- |
| Report | `encoder-comparison.md` | `decoder-comparison.md` |
| Measurements | `encoder-comparison.csv` | `decoder-comparison.csv` |
| Environment | `encoder-comparison-environment.json` | `decoder-comparison-environment.json` |
| Index and quality pages | `encoders/README.md`, `encoders/q0.md`–`q11.md` | `decoders/README.md`, `decoders/q0.md`–`q11.md` |
| Charts | `encoders/charts/` | `decoders/charts/` |

Each chart directory contains `overview.svg`. Install plotting support in an
isolated environment if needed:

```sh
python3 -m venv /tmp/brotli-plots
/tmp/brotli-plots/bin/python -m pip install matplotlib==3.10.8
```

Use that environment's Python for the generation commands below.

## Encoder comparison

Run from the repository root:

```sh
git submodule update --init --recursive
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --locked -- --test
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --locked -- --save-baseline my-comparison
python3 benchmarks/comparison/report.py --baseline my-comparison --csv /tmp/my-comparison.csv
```

Use a fresh baseline name for each complete run. The standalone package owns its
lockfile and writes to `benchmarks/comparison/target/criterion/`. Competitor crates
are dependencies only of this unpublished package. Existing harnesses, their
dependency resolution, and root `target/criterion/` results remain independent.

The suite contains **432 cases**: eight corpora, q0–q11 for four implementations,
and q0–q5 for Burli. Unsupported qualities are omitted, never clamped. Every case
uses generic mode, window bits 22, automatic block size, a complete known input,
no custom dictionary, and no explicit flushes. Equal numeric quality describes
each encoder's effort policy; it does not guarantee equal output size.

| Implementation | Version | Timed API |
| --- | --- | --- |
| Google C Brotli | 1.2.0, pinned submodule | `BrotliEncoderCompress` |
| mbrotli | Local checkout | Construct `Compressor`, then `compress` |
| [Rust brotli](https://docs.rs/brotli/9.0.0/brotli/) | 9.0.0 | `BrotliCompress` |
| [simd-brotli](https://docs.rs/simd-brotli/10.0.1/simd_brotli/) | 10.0.1 | `BrotliCompress` |
| [burli](https://github.com/paddor/burli) | 0.3.3 | `compress_with_options` |

This is **cold end-to-end compression**: configuration, construction, scratch and
destination allocation, encoding, and disposal occur inside each iteration.
The two `BrotliCompress` helpers include their native 4 KiB I/O adaptation.
No implementation retains workspace. Native C one-shot output rewrites are
included; validation requires decoded equality, not compressed byte identity.

The corpora are empty input, a 44-byte text, vendored `alice29.txt`, Alice repeated
to 1 MiB, structured 64 KiB binary, deterministic pseudorandom bytes at 64 KiB and
1 MiB, and 1 MiB of repeated `a` bytes. Construction and C-decoder validation of
all 432 outputs finish before timing starts. Missing vendor data fails the build.
`sizes.csv` records the validated output lengths.

Defaults are 20 samples, one second of warmup, and three seconds of measurement
per case. Criterion options override them. A focused timing run is:

```sh
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --locked -- 'alice29/q5/'
```

Filtered runs still validate the full matrix. The exporter rejects incomplete
timing sweeps and checks input lengths. Export immediately after the matching run:
`sizes.csv` describes the most recent preflight. Archive that file with the named
baseline for later analysis. CSV columns include mean nanoseconds and 95%
confidence bounds, MiB/s, `C time / encoder time`, compressed bytes, and
`compressed / input`. For empty input, throughput is zero and the compressed
fraction is undefined; compare latency.

Rebuild the checked-in encoder pages and charts with Matplotlib 3.10.8:

```sh
python3 benchmarks/comparison/quality_docs.py \
  --csv docs/benchmarks/encoder-comparison.csv \
  --environment docs/benchmarks/encoder-comparison-environment.json \
  --report docs/benchmarks/encoder-comparison.md \
  --output docs/benchmarks/encoders
python3 benchmarks/comparison/plot.py \
  --csv docs/benchmarks/encoder-comparison.csv \
  --output docs/benchmarks/encoders/charts \
  --subtitle 'AMD Ryzen 9 7950X; 20 samples; CPU 1; 2026-10-29'
```

`quality_docs.py` writes the index, twelve quality pages and their detailed
charts. `plot.py` writes `overview.svg`, `throughput.svg` and `size.svg` into
the same charts directory. All eight corpora contribute to the medians.
The published encoder CSV is `enc-2026-10-29-amd`, with its
[size manifest](benchmarks/encoder-comparison-2026-10-29/sizes.csv); the decoder CSV is
`dec-2026-10-29-amd`, with its
[size manifest](benchmarks/decoder-comparison-2026-10-29/sizes.csv). Both were recorded on
2026-10-29 using Rust 1.99.1 and GCC 15.2 on an AMD Ryzen 9 7950X Linux VDS,
one process at a time pinned to logical CPU 1. Sampling is 20 samples, 1 s warmup
and 3 s requested measurement per case. No builds, tests, fuzzers or other
benchmarks ran concurrently. Each environment record identifies the measured
uncommitted checkout, lockfiles and frozen executable. Regenerating charts uses
the CSV and does not rerun measurements.

## Decoder comparison

The [decoder results](benchmarks/decoders/README.md) compare Google C, mbrotli,
Rust brotli and Burli on **identical compressed streams**, prepared by Google C
at q0–q11, generic mode and window 22, from the same eight inputs as the encoder
comparison: empty, 44-byte tiny text, Alice, cyclic Alice at 1 MiB, structured
binary at 64 KiB, random bytes at 64 KiB and 1 MiB, and repeated `a` at 1 MiB.
All **384 cases** must restore the original bytes before timing starts.
Burli decodes all source qualities. SIMD Brotli is omitted because its decoder
re-exports the Rust `brotli-decompressor` project. The lockfile resolves 6.0.1
for Rust brotli and 5.0.3 for SIMD Brotli; this comparison measures the former.

```sh
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench decoders --locked -- --test
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench decoders --locked -- --save-baseline my-decoders
python3 benchmarks/comparison/report.py --decoding --baseline my-decoders --csv /tmp/my-decoders.csv
```

Results live in `benchmarks/comparison/target/criterion-decoders/`, independent
of encoder and root API measurements. Archive its `sizes.csv` with each fresh
named baseline. Filtering, for example `'alice29/q5/'`, still validates the
complete matrix; a full sweep is required for export. Sampling defaults match
the encoder comparison and accept the same Criterion overrides.

| Decoder | Version | Timed API |
| --- | --- | --- |
| Google C | 1.2.0, pinned vendor revision | `BrotliDecoderDecompress` into a newly allocated, initialized output |
| mbrotli | Local checkout | Construct `Decompressor`, then `decompress` |
| Rust brotli | 9.0.0 | `BrotliDecompress` into a new Vec, native 4 KiB I/O buffers |
| Burli | 0.3.3 | `burli::decompress` |

This measures cold native APIs, including construction, allocation, decode and
disposal. C requires the known output capacity; the Rust Vec helpers discover
output size while decoding. No decoder retains state between iterations.
Throughput counts **restored bytes**, not compressed input bytes. In the CSV,
`input_bytes` is the original corpus length and `compressed_bytes` is the
identical compressed input size. Quality is the **source encoder's** setting.
Empty input has latency but no meaningful throughput or compression fraction.

Rebuild the checked-in overview, twelve quality pages and thirteen SVG charts
with Matplotlib 3.10.8:

```sh
python3 benchmarks/comparison/decoder_docs.py \
  --csv docs/benchmarks/decoder-comparison.csv \
  --environment docs/benchmarks/decoder-comparison-environment.json \
  --report docs/benchmarks/decoder-comparison.md \
  --output docs/benchmarks/decoders
```

The overview takes the median of eight per-dataset C-time/decoder-time ratios,
with equal weight. A separate column computes direct Burli-time/mbrotli-time
ratios before taking their median. Empty and tiny inputs have equal weight
in the median and use latency panels. Per-quality panels retain
all individual mean confidence bounds. Shared compressed sizes are listed
alongside restored lengths instead of ranking decoders by size. See the
[run report](benchmarks/decoder-comparison.md) for environment and limitations.

## Sharded runs

The published encoder and decoder sweeps run serially, one process at a time.
For exploratory runs on a host with idle cores, the matrix can be split by
corpus. Every implementation of a case must still run under the same recorded
conditions. Concurrent shards share caches, memory bandwidth and the package's
turbo budget; their latency and ratios can differ from an otherwise idle run.
Record all lanes and concurrent workloads explicitly.

Build the harness once, then run its executable directly so that concurrent
`cargo bench` invocations do not wait on the build directory lock. The
harness writes to fixed directories under `benchmarks/comparison/target/`,
separate benchmark IDs land in separate directories, and every shard writes
the same deterministic `sizes.csv` during its preflight:

```sh
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --bench decoders --locked --no-run
cd benchmarks/comparison
enc=$(ls -t target/release/deps/implementations-* | grep -v '\.d$' | head -1)
dec=$(ls -t target/release/deps/decoders-* | grep -v '\.d$' | head -1)
lane() { taskset -c "$1" "$2" --bench --save-baseline "$3" "$4"; }
{ lane 0 "$enc" my-enc '^implementations/cold/(empty|tiny-text)/'; lane 0 "$enc" my-enc '^implementations/cold/(alice29|text-1m)/'; } &
{ lane 2 "$enc" my-enc '^implementations/cold/(binary-64k|random-64k)/'; lane 2 "$enc" my-enc '^implementations/cold/(random-1m|repeated-1m)/'; } &
{ lane 4 "$dec" my-dec '^decoders/cold/(empty|tiny-text)/'; lane 4 "$dec" my-dec '^decoders/cold/(alice29|text-1m)/'; } &
{ lane 6 "$dec" my-dec '^decoders/cold/(binary-64k|random-64k)/'; lane 6 "$dec" my-dec '^decoders/cold/(random-1m|repeated-1m)/'; } &
wait
cd ../..
python3 benchmarks/comparison/report.py --baseline my-enc --csv /tmp/my-enc.csv
python3 benchmarks/comparison/report.py --decoding --baseline my-dec --csv /tmp/my-dec.csv
```

Choose one logical CPU per physical core (`lscpu -e=CPU,CORE`). The example
above is an optional exploratory layout, not the published run's topology.
Use a serial sweep when publishing comparisons between libraries, and do not
mix measurements from different host-load conditions into one named baseline.
The root API suites remain independent and should also record their exact
affinity, concurrency and API mode.

## API benchmarks

Run these harnesses to compare specific API modes:

```sh
cargo bench --bench compress --locked
cargo bench --bench decompress --locked
cargo bench --bench parallel --locked
cargo bench --bench track_b --features experimental --locked
```

`compress` covers cold, reused, presized, tiny, streaming, flush, dictionary,
and universal cases against a matched C streaming oracle. `parallel` covers
task counts and source adapters. `track_b` covers experimental formats.
Their contracts differ from the cold native one-shot comparison. The
per-case 95%-of-C gate and its Python tests remain available:

```sh
cargo bench --bench compress --locked -- --save-baseline candidate
python3 scripts/compare_benchmarks.py --baseline candidate --expected-cases 682 --csv /tmp/candidate.csv
python3 -m unittest discover -s scripts -p 'test_*.py'
```

## Checks and profiling

The standalone package needs its own checks:

```sh
cargo fmt --manifest-path benchmarks/comparison/Cargo.toml --all -- --check
cargo clippy --manifest-path benchmarks/comparison/Cargo.toml --all-targets --locked -- -D warnings
cargo test --manifest-path benchmarks/comparison/Cargo.toml --release --locked
python3 -m unittest discover -s benchmarks/comparison -p 'test_*.py'
cargo llvm-cov --manifest-path benchmarks/comparison/Cargo.toml --release --locked --benches -- --test
```

Keep instrumented profiling separate from timing:

```sh
cargo run --release --features hotpath-cpu --example profile_compressor -- brotli-ffi/vendor/brotli/tests/testdata/alice29.txt
cargo run --release --features hotpath-alloc --example profile_compressor -- brotli-ffi/vendor/brotli/tests/testdata/alice29.txt
```

On x86_64 Linux, `hotpath-callgrind` adds per-function instruction counts from
Valgrind Callgrind, which are reproducible across runs of one commit (at most
0.05% apart). The `hotpath benchmark` workflow runs in merged mode on every
pull request: one build runs natively for timing and allocations, then under
Callgrind, which merges its instruction counts into the native report and
uploads it to hotpath Cloud, judged by `hotpath/policy.toml`. Counts are
judged, timing is shown but not judged; compare counts only within one
Valgrind version, Rust toolchain and runner image:

```sh
cargo build --release --example profile_compressor --features hotpath-alloc,hotpath-callgrind
HOTPATH_OUTPUT_FORMAT=json HOTPATH_OUTPUT_PATH=native.json \
  target/release/examples/profile_compressor brotli-ffi/vendor/brotli/tests/testdata/alice29.txt
HOTPATH_OUTPUT_FORMAT=json HOTPATH_MERGE_REPORT=native.json HOTPATH_OUTPUT_PATH=merged.json \
  valgrind -q --tool=callgrind --instr-atstart=no \
  target/release/examples/profile_compressor brotli-ffi/vendor/brotli/tests/testdata/alice29.txt
```

Record revision, lockfile, compilers, CPU, target flags, affinity, corpus identity,
settings, API mode, sizes, and timing intervals. Generated Criterion and coverage
files are local artifacts. Short runs on shared hosts provide exploratory
evidence, not universal performance claims.
