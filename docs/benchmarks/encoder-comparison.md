# Compression comparison — 2026-09-28

[Benchmark index](README.md) · [Results by quality](encoders/README.md)

The [432-case CSV](encoder-comparison.csv) and
[environment record](encoder-comparison-environment.json) describe the working
tree based on `17b3d315`, recorded as `enc-2026-09-28`. The tree's
uncommitted changes are in the decoder and the C ABI; encoder sources are
those of the commit, which adds uninitialized-output methods to the
compressor. Competitors are unchanged: Rust brotli 9.0.0, simd-brotli 10.0.1
and Burli 0.3.3. The [size manifest](encoder-comparison-2026-09-28/sizes.csv)
is archived with the run and is identical to that of the September 26 sweep
it replaces; the environment records source and executable hashes.

This sweep ran as four corpus shards on separate cores, alongside the decoder
sweep and the root API benchmarks: eight benchmark processes at once. See
[interpretation limits](#interpretation-limits) before comparing its absolute
timings with earlier single-core sweeps.

## Final measurements

![Median speed and output relative to C by quality](encoders/charts/overview.svg)

Each quality summarizes eight equally weighted datasets. Speed / C is C mean
latency divided by the encoder's mean latency for the same input; output / C is
encoder bytes divided by C bytes. The summary takes the median of those eight
ratios, including empty and tiny input. These are not median Criterion sample
times. Higher speed and lower output are better.

| Quality | mbrotli median speed / C ↑ | mbrotli median output / C ↓ |
| --- | ---: | ---: |
| 0 | 1.161× | 1.000× |
| 1 | 1.167× | 1.000× |
| 2 | 1.151× | 1.000× |
| 3 | 1.066× | 1.000× |
| 4 | 1.043× | 1.000× |
| 5 | 0.975× | 1.000× |
| 6 | 0.949× | 1.000× |
| 7 | 0.966× | 1.000× |
| 8 | 0.898× | 1.000× |
| 9 | 2.868× | 1.000× |
| 10 | 1.169× | 1.000× |
| 11 | 1.231× | 1.000× |

mbrotli has a lower mean latency than C in 59 of 96 shared cases and the lowest
mean among supported implementations in 48 of 96 cases. These counts compare
point estimates, not statistical significance. In 37 cases, mbrotli's 95% mean
timing interval is wholly below every competitor's interval. The medians also
retain qualities where mbrotli is slower than C.

For Alice at q4, mbrotli measures 83.65 MiB/s against C's 89.25 MiB/s, both
producing 55,504 bytes; Burli measures 85.36 MiB/s with 57,813 bytes. At q5,
mbrotli measures 53.38 MiB/s against C's 57.61 MiB/s, both producing 52,809
bytes. At q11, mbrotli measures 1.38 MiB/s against C's 1.10 MiB/s, both
producing 46,487 bytes; SIMD Brotli measures 1.29 MiB/s with 46,493 bytes.

Against the September 26 sweep every output size is unchanged, and every
implementation, C included, is up to 6% slower in absolute terms on most corpora:
the cost of sharing the cache and turbo budget with seven other benchmark
processes, not of code changes. Ratios to C moved within this host's
run-to-run variation (59 cases faster than C, against 58): per-quality
medians shifted by 1-8% in both directions (q3 1.145× → 1.066×, q4 0.984× →
1.043×, q9 2.605× → 2.868×). Empty input is the exception: mbrotli's
geometric-mean speed there fell 16% while C's did not change, because its
allocation-bound path is the most sensitive to the shared load. A single-core
A/B of the same encoder against the commit before the uninitialized-output
change, run the same day, measured mbrotli's empty-input latency at 26.8-28.4
ns against 26.5-28.6 ns before, and a median mbrotli/C ratio change of +0.2%
across all 96 cases.

The [quality pages](encoders/README.md) retain all datasets, all implementations,
and exact timings with 95% mean confidence bounds. Burli supports q0–q5 only.
Equal quality numbers describe each encoder's effort policy and do not imply
equal output size.

mbrotli and Google C produce equal output lengths in all 96 shared cases in
this run. Equal lengths alone do not establish compressed byte identity; the
greedy differential tests check byte identity with Google C separately.

## Measurement contract

| Setting | Recorded value |
| --- | --- |
| Host | Intel Core i7-13700KF, x86_64, WSL2 |
| Affinity | Four corpus shards, two per lane, on logical CPUs 0 and 2; four other lanes on CPUs 4-14 ran concurrently |
| Rust | rustc 1.98.1; release defaults; runtime SIMD dispatch |
| C compiler | GCC 11.4.0; vendored release defaults |
| C Brotli | 1.2.0; commit `4508218e7fef90fa4273286f7a415065946f2c43` |
| Rust brotli / simd-brotli / burli | 9.0.0 / 10.0.1 / 0.3.3 |
| Compression | Generic mode, window 22, complete known input, no dictionary or explicit flush |
| API | Cold native serial helpers; construction, allocation, compression, and disposal timed |
| Sampling | 20 samples; 1 s warmup; 3 s requested measurement per case |
| Validation | All 432 outputs decoded to the original input through Google C Brotli before timing |

Inputs are empty, 44-byte text, vendored `alice29.txt` (152,089 bytes), cyclic
Alice text at 1 MiB, structured binary at 64 KiB, deterministic pseudorandom
bytes at 64 KiB and 1 MiB, and 1 MiB of repeated `a` bytes. Corpus construction
and validation occur outside timing. The environment record hashes the corpus
generator, Alice source, lockfiles, and benchmark executable.

No encoder retains workspace between iterations. Rust Brotli and SIMD Brotli
include their native 4 KiB I/O adapters. The C encoder uses its native one-shot
API, including its output rewrites. Round-trip equality is required; compressed
byte identity across implementations is not. Empty input has latency and output
size but no meaningful throughput or compressed/input fraction.

## Reproduction

Run from the repository root; use a fresh baseline name when repeating timings.
The [benchmark guide](../benchmarking.md#sharded-runs) describes the sharded
run; a single-core sweep is one command:

```sh
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --locked -- --test
taskset -c 2 cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --locked -- --save-baseline enc-2026-09-28
python3 benchmarks/comparison/report.py --baseline enc-2026-09-28 --csv docs/benchmarks/encoder-comparison.csv
python3 benchmarks/comparison/quality_docs.py --csv docs/benchmarks/encoder-comparison.csv --environment docs/benchmarks/encoder-comparison-environment.json --report docs/benchmarks/encoder-comparison.md --output docs/benchmarks/encoders
python3 benchmarks/comparison/plot.py --csv docs/benchmarks/encoder-comparison.csv --output docs/benchmarks/encoders/charts --subtitle 'i7-13700KF; working tree; 20 samples; 8 parallel lanes; 2026-09-28'
```

Plotting uses Matplotlib 3.10.8. Criterion extends slow cases to collect the
requested samples. The exporter rejects incomplete matrices and mismatched
input lengths. Export immediately after timing and archive `sizes.csv` with
the named baseline: a later preflight replaces that shared manifest. This
run's [size manifest](encoder-comparison-2026-09-28/sizes.csv) is checked in.
Raw samples remain local under `benchmarks/comparison/target/criterion/`.
Chart regeneration reuses the CSV; it does not rerun timings.

## Interpretation limits

This is a single sweep on one WSL2 host. Eight single-threaded benchmark
processes ran at once on separate cores and shared the last-level cache,
memory bandwidth and the package's turbo budget, so absolute timings are
3-10% below a single-core sweep and cases of tens of nanoseconds move most.
Every implementation of a case ran in the same process under the same load,
so ratios to C are the comparable quantity. Affinity restricts CPU migration
but does not control frequency, thermal state, or host scheduling.
Implementation order is fixed. The lowest mean does not necessarily imply a
statistically significant lead; confidence bounds do not capture every source
of host or allocator variation. Builds of fuzz targets and profiling harnesses
ran on logical CPUs 16-23 during part of the sweep.

The suite measures cold serial compression. Streaming, retained workspace,
parallel tasks, dictionaries, and experimental formats have separate root API
benchmarks and are not represented by these results. See the
[benchmark guide](../benchmarking.md) and [harness specification](../../architecture/benchmark-comparison.md).
