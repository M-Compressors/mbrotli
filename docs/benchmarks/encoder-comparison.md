# Compression comparison — 2026-10-09

[Benchmark index](README.md) · [Results by quality](encoders/README.md)

The [432-case CSV](encoder-comparison.csv) and
[environment record](encoder-comparison-environment.json) describe the working
tree based on v0.5.6 (`dba6a473`), recorded as `enc-2026-10-09`, against Google C Brotli
1.2.0, Rust brotli 9.0.0, simd-brotli 10.0.1 and Burli 0.3.3. The run's
[size manifest](encoder-comparison-2026-10-09/sizes.csv) is archived with it;
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
| 0 | 1.171× | 1.000× |
| 1 | 1.123× | 1.000× |
| 2 | 1.152× | 1.000× |
| 3 | 1.156× | 1.000× |
| 4 | 1.011× | 1.000× |
| 5 | 0.960× | 1.000× |
| 6 | 1.038× | 1.000× |
| 7 | 0.850× | 1.000× |
| 8 | 0.944× | 1.000× |
| 9 | 2.930× | 1.000× |
| 10 | 1.330× | 1.000× |
| 11 | 1.589× | 1.000× |

mbrotli has a lower mean latency than C in 66 of 96 shared cases and the lowest
mean among supported implementations in 53 of 96 cases. These counts compare
point estimates, not statistical significance. In 39 cases, mbrotli's 95% mean
timing interval is wholly below every competitor's interval. The medians also
retain qualities where mbrotli is slower than C.

For Alice at q4, mbrotli measures 87.16 MiB/s against C's 90.19 MiB/s, both
producing 55,504 bytes; Burli measures 86.81 MiB/s with 57,813 bytes. At q5,
mbrotli measures 56.56 MiB/s against C's 60.61 MiB/s, both producing 52,809
bytes. At q11, mbrotli measures 1.66 MiB/s against C's 1.04 MiB/s, both
producing 46,487 bytes; SIMD Brotli measures 1.27 MiB/s with 46,493 bytes.

Against the previous run (`enc-2026-10-02`) the q10 and q11 medians rose from
1.172× and 1.299× to 1.330× and 1.589× of C, from the distance-cache prefilter,
the vector dictionary compare and the UTF-8 early exit. Output sizes are
unchanged in all 432 cases and the size manifests are identical. Other
qualities moved within the host variation described under
[interpretation limits](#interpretation-limits).

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
taskset -c 2 cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --locked -- --save-baseline enc-2026-10-09
python3 benchmarks/comparison/report.py --baseline enc-2026-10-09 --csv docs/benchmarks/encoder-comparison.csv
python3 benchmarks/comparison/quality_docs.py --csv docs/benchmarks/encoder-comparison.csv --environment docs/benchmarks/encoder-comparison-environment.json --report docs/benchmarks/encoder-comparison.md --output docs/benchmarks/encoders
python3 benchmarks/comparison/plot.py --csv docs/benchmarks/encoder-comparison.csv --output docs/benchmarks/encoders/charts --subtitle 'i7-13700KF; working tree; 20 samples; 8 parallel lanes; 2026-10-09'
```

Plotting uses Matplotlib 3.10.8. Criterion extends slow cases to collect the
requested samples. The exporter rejects incomplete matrices and mismatched
input lengths. Export immediately after timing and archive `sizes.csv` with
the named baseline: a later preflight replaces that shared manifest. This
run's [size manifest](encoder-comparison-2026-10-09/sizes.csv) is checked in.
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
of host or allocator variation. Nothing else ran on the host during the sweep,
which started four minutes after a reboot at a load average of 0.13.

Ratios to C are not stable to a few percent between sweeps on this host: C's
own mean latency moved by up to ±15% per case against the previous run. Every
case whose ratio fell more than 5% was re-timed (24 encoder cases); those that
stayed low were compared with callgrind across `5f39a1d0`, v0.5.6 and this
tree. Their instruction counts and page faults agree within 0.7%, so the
remaining shifts, concentrated in empty, tiny and random inputs at q0-q6, are
host effects. This tree was also compared with v0.5.6 directly: the same
Criterion harness built from both, run at once on paired lanes over all 96
mbrotli and C cases, and a one-shot harness alternating the two builds on one
otherwise idle core. Paired lanes leave per-case noise of up to ±10%, untouched
qualities included. On the idle core, the cases those runs flagged are within
1.2% of v0.5.6 or faster: structured binary is level at q7 and q8 (0.0% and
+0.6%) and 4-5% faster at q10 and q11, random 64 KiB at q8 +1.2%, Alice at q8
2% faster, tiny text at q10 level, and random 1 MiB at q10 13% faster. That case's low
ratio in this sweep (0.85× C, 113 ms against C's 138 ms when timed alone) is
sensitivity to the neighbouring lanes, which v0.5.6 shares.

Cold 1 MiB inputs at q7 and q8, and Alice at q7-q9, are bimodal on this host:
when the allocator trims a freed peak, the next iteration faults its pages back
in, and a parallel sweep can catch either mode for a whole case. In this sweep
Alice at q8 sits in the slow mode, 5.49 ms against C's 3.63 ms, and Alice at
q7 takes 4.24 ms against 3.45 ms; random 1 MiB at q7 and q8, slow in the
previous run, is level with C at 2.33 and 2.66 ms. That is why the q7 and q8
medians stay below C.

The suite measures cold serial compression. Streaming, retained workspace,
parallel tasks, dictionaries, and experimental formats have separate root API
benchmarks and are not represented by these results. See the
[benchmark guide](../benchmarking.md) and [harness specification](../../architecture/benchmark-comparison.md).
