# Decompression comparison — 2026-09-28

[Benchmark index](README.md) · [All quality pages](decoders/README.md) ·
[Published CSV](decoder-comparison.csv)

The published 384 rows cover four decoders on eight identical C-produced inputs
at each source quality, recorded as `dec-2026-09-28` with Rust brotli 9.0.0
(decoder `brotli-decompressor` 6.0.1) and Burli 0.3.3.
mbrotli's median speed relative to Burli is **1.004×**
across all 96 corpus/quality pairs; Burli is faster in 47 of them. Empty and tiny
inputs have the same weight as large inputs. Per-workload results include cases
where mbrotli is slower.

| Source quality | Google C | mbrotli | Rust brotli | Burli | mbrotli / Burli |
| --- | ---: | ---: | ---: | ---: | ---: |
| q0 | 1.000× | 3.586× | 0.379× | 3.298× | 0.978× |
| q1 | 1.000× | 3.580× | 0.375× | 3.523× | 1.017× |
| q2 | 1.000× | 3.786× | 0.597× | 3.471× | 1.015× |
| q3 | 1.000× | 3.297× | 0.567× | 3.186× | 1.016× |
| q4 | 1.000× | 3.777× | 0.577× | 3.493× | 1.057× |
| q5 | 1.000× | 3.225× | 0.566× | 3.260× | 0.979× |
| q6 | 1.000× | 3.227× | 0.559× | 3.185× | 0.959× |
| q7 | 1.000× | 3.090× | 0.572× | 3.189× | 1.005× |
| q8 | 1.000× | 3.157× | 0.583× | 3.104× | 0.990× |
| q9 | 1.000× | 3.231× | 0.596× | 3.412× | 0.970× |
| q10 | 1.000× | 3.130× | 0.571× | 3.172× | 1.021× |
| q11 | 1.000× | 3.185× | 0.613× | 3.177× | 1.036× |

Each library column is the median of eight C mean time / decoder mean time
ratios. The last column uses direct Burli time / mbrotli time ratios. The overall
value takes the median of all 96 direct ratios, not an average of quality medians.
Higher is faster; medians do not establish statistical significance.

Against the September 26 publication, compressed inputs are identical. The
commit this tree is based on added uninitialized output to the decoder, and
its first version matched on an output-sink enum inside the decode loop: a
single-core A/B against the commit before it measured `decompress` 4-7%
slower on Alice, cyclic Alice and structured binary, with Google C unchanged,
and callgrind counted 9% more executed instructions on Alice. The working tree
makes the decoder generic over the sink instead, which brings the instruction
count to within 0.4% of the earlier decoder. This sweep measures that tree.

All four decoders, Google C included, are up to 10% slower in absolute terms on
most corpora than on September 26, because eight benchmark processes shared the
host (see [limits](#provenance-and-limits)); mbrotli's speed relative to C moved
within host variation on every corpus (speed against September 26, geometric
mean over the twelve qualities: Alice 0.984 mbrotli against 0.970 C, cyclic
Alice 0.958 against 0.956, structured binary 0.940 against 0.924). By dataset,
mbrotli leads Burli on Alice and cyclic Alice (median 1.21× and 1.15× Burli's
speed), is level on random input and structured binary (1.02×, down to 0.82× at
one quality), and trails on empty input (0.71×) and repeated bytes (median
0.98×, 0.67× at one quality). Tiny text is level at the median (1.03×) but stays
Burli's where a first decode builds context-modelled tables (down to 0.62×).
This suite times only `decompress`; `decompress_to_slice`,
`decompress_to_uninit` and the streaming sessions are measured by the root
`decompress` benchmark.

## Measurement contract

Cold native APIs include construction, allocation, decoding and disposal. C gets
the known output capacity; Rust brotli includes 4 KiB I/O adaptation. Throughput
counts restored bytes. The shared input sizes belong to the source streams,
not to a decoder. Every case must restore the original bytes before timing.

The corpus is empty input, tiny text, Alice, cyclic Alice at 1 MiB, structured
binary at 64 KiB, random bytes at 64 KiB and 1 MiB, and repeated `a` at 1 MiB.
Parameters are generic mode and window 22 on an i7-13700KF/WSL2 host. Sampling uses the
harness defaults: 20 samples, 1 s warmup and at least 3 s measurement per case.

## Provenance and limits

The [environment record](decoder-comparison-environment.json) hashes this CSV,
the lockfiles, harness sources and the timed executable, and names the baseline
commit. The working tree adds the uncommitted decoder changes described above
to that commit. The run's
[size manifest](decoder-comparison-2026-09-28/sizes.csv) is archived.

The sweep ran as four corpus shards on logical CPUs 4 and 6 while the encoder
sweep and the root API benchmarks ran on six other cores: eight benchmark
processes at once, sharing the last-level cache, memory bandwidth and turbo
budget. Absolute timings are therefore below a single-core sweep; every
decoder of a case ran in the same process under the same load, so ratios are
the comparable quantity. Builds of fuzz targets and profiling harnesses ran on
logical CPUs 16-23 during part of the sweep.

One shared host, fixed implementation order and uncontrolled clocks/thermals can
bias results beyond sampling intervals. These data cover cold serial decoding
of standard-window C streams; retained state, streaming, dictionaries and other
producers require separate measurements.

## Reproduce

```sh
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench decoders --locked -- --test
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench decoders --locked -- --save-baseline my-decoders
python3 benchmarks/comparison/report.py --decoding --baseline my-decoders --csv /tmp/my-decoders.csv
```

Use a fresh baseline name and archive its size manifest, source/binary identity,
commands and environment together. [Benchmarking](../benchmarking.md) covers
sharded runs, report generation and the separate root API benchmarks.
