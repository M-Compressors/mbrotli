# Compression comparison — 2026-10-02

[Benchmark index](README.md) · [Results by quality](encoders/README.md)

The [432-case CSV](encoder-comparison.csv) and
[environment record](encoder-comparison-environment.json) describe the working
tree based on `5f39a1d0`, recorded as `enc-2026-10-02`, against Google C Brotli
1.2.0, Rust brotli 9.0.0, simd-brotli 10.0.1 and Burli 0.3.3. The run's
[size manifest](encoder-comparison-2026-10-02/sizes.csv) is archived with it;
the environment record holds the source and executable hashes.

The sweep ran as four corpus shards on separate cores, alongside the decoder
sweep: eight benchmark processes at once. See
[interpretation limits](#interpretation-limits) before reading absolute timings.

## Final measurements

![Median speed and output relative to C by quality](encoders/charts/overview.svg)

Each quality summarizes eight equally weighted datasets. Speed / C is C mean
latency divided by the encoder's mean latency for the same input; output / C is
encoder bytes divided by C bytes. The summary takes the median of those eight
ratios, including empty and tiny input. These are not median Criterion sample
times. Higher speed and lower output are better.

| Quality | mbrotli median speed / C ↑ | mbrotli median output / C ↓ |
| --- | ---: | ---: |
| 0 | 1.090× | 1.000× |
| 1 | 1.143× | 1.000× |
| 2 | 1.205× | 1.000× |
| 3 | 1.125× | 1.000× |
| 4 | 1.026× | 1.000× |
| 5 | 1.004× | 1.000× |
| 6 | 0.927× | 1.000× |
| 7 | 0.861× | 1.000× |
| 8 | 0.896× | 1.000× |
| 9 | 2.804× | 1.000× |
| 10 | 1.172× | 1.000× |
| 11 | 1.299× | 1.000× |

mbrotli has a lower mean latency than C in 60 of 96 shared cases and the lowest
mean among supported implementations in 51 of 96 cases. These counts compare
point estimates, not statistical significance. In 42 cases, mbrotli's 95% mean
timing interval is wholly below every competitor's interval. The medians also
retain qualities where mbrotli is slower than C.

For Alice at q4, mbrotli measures 85.26 MiB/s against C's 83.63 MiB/s, both
producing 55,504 bytes; Burli measures 88.96 MiB/s with 57,813 bytes. At q5,
mbrotli measures 54.24 MiB/s against C's 57.75 MiB/s, both producing 52,809
bytes. At q11, mbrotli measures 1.29 MiB/s against C's 1.04 MiB/s, both
producing 46,487 bytes; SIMD Brotli measures 1.21 MiB/s with 46,493 bytes.

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
| Affinity | Four corpus shards, one per lane, on logical CPUs 0, 2, 4 and 6; the decoder sweep's four lanes on CPUs 8-14 ran concurrently |
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
taskset -c 2 cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --locked -- --save-baseline enc-2026-10-02
python3 benchmarks/comparison/report.py --baseline enc-2026-10-02 --csv docs/benchmarks/encoder-comparison.csv
python3 benchmarks/comparison/quality_docs.py --csv docs/benchmarks/encoder-comparison.csv --environment docs/benchmarks/encoder-comparison-environment.json --report docs/benchmarks/encoder-comparison.md --output docs/benchmarks/encoders
python3 benchmarks/comparison/plot.py --csv docs/benchmarks/encoder-comparison.csv --output docs/benchmarks/encoders/charts --subtitle 'i7-13700KF; working tree; 20 samples; 8 parallel lanes; 2026-10-02'
```

Plotting uses Matplotlib 3.10.8. Criterion extends slow cases to collect the
requested samples. The exporter rejects incomplete matrices and mismatched
input lengths. Export immediately after timing and archive `sizes.csv` with
the named baseline: a later preflight replaces that shared manifest. This
run's [size manifest](encoder-comparison-2026-10-02/sizes.csv) is checked in.
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
of host or allocator variation. Nothing else ran on the host during the sweep.

Cold 1 MiB inputs at q7 and q8, and Alice at q7-q9, are bimodal on this host:
when the allocator trims a freed peak, the next iteration faults its pages back
in, and a parallel sweep can catch either mode for a whole case. In this sweep
Alice at q7 and q8 and random 1 MiB at q8 sit in the slow mode: 5.34, 6.00 and
6.63 ms, against 3.65, 4.38 and 3.41-3.53 ms for the same build timed alone on
one core, where C takes 3.06-3.11, 3.47-3.51 and 3.12-3.13 ms. That is why the
q7 and q8 medians fall further below C here than mbrotli's single-core 1.1-1.25
times C's time on those inputs.

The suite measures cold serial compression. Streaming, retained workspace,
parallel tasks, dictionaries, and experimental formats have separate root API
benchmarks and are not represented by these results. See the
[benchmark guide](../benchmarking.md) and [harness specification](../../architecture/benchmark-comparison.md).
