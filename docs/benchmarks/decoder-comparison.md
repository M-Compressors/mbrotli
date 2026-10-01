# Decompression comparison — 2026-10-01

[Benchmark index](README.md) · [All quality pages](decoders/README.md) ·
[Published CSV](decoder-comparison.csv)

The published 384 rows cover four decoders on eight identical C-produced inputs
at each source quality, recorded as `dec-2026-10-01` with Rust brotli 9.0.0
(decoder `brotli-decompressor` 6.0.1) and Burli 0.3.3.
mbrotli's median speed relative to Burli is **0.995×**
across all 96 corpus/quality pairs; Burli is faster in 54 of them. Empty and tiny
inputs have the same weight as large inputs. Per-workload results include cases
where mbrotli is slower.

| Source quality | Google C | mbrotli | Rust brotli | Burli | mbrotli / Burli |
| --- | ---: | ---: | ---: | ---: | ---: |
| q0 | 1.000× | 3.770× | 0.363× | 3.501× | 0.972× |
| q1 | 1.000× | 3.567× | 0.338× | 3.476× | 0.995× |
| q2 | 1.000× | 3.631× | 0.580× | 3.531× | 1.037× |
| q3 | 1.000× | 3.102× | 0.566× | 3.150× | 0.985× |
| q4 | 1.000× | 3.824× | 0.571× | 3.618× | 1.053× |
| q5 | 1.000× | 3.083× | 0.604× | 3.099× | 0.975× |
| q6 | 1.000× | 3.163× | 0.524× | 3.213× | 0.991× |
| q7 | 1.000× | 3.129× | 0.587× | 3.165× | 0.990× |
| q8 | 1.000× | 3.198× | 0.537× | 3.214× | 0.956× |
| q9 | 1.000× | 3.118× | 0.564× | 3.050× | 0.981× |
| q10 | 1.000× | 3.174× | 0.571× | 3.159× | 1.011× |
| q11 | 1.000× | 3.089× | 0.563× | 3.073× | 1.033× |

Each library column is the median of eight C mean time / decoder mean time
ratios. The last column uses direct Burli time / mbrotli time ratios. The overall
value takes the median of all 96 direct ratios, not an average of quality medians.
Higher is faster; medians do not establish statistical significance.

Against the September 28 publication, compressed inputs are identical. The
tree this sweep measures carries the 2026-09-30 command-loop changes (commit
`a3896d13`), which callgrind and single-core runs show cutting instructions
and branches; in this parallel sweep mbrotli's speed relative to C moved
within host variation instead (speed against September 28, geometric mean
over the twelve qualities: Alice 0.953 mbrotli against 0.977 C, cyclic Alice
0.994 against 0.970, structured binary 1.006 against 0.981, random 1 MiB 0.965
against 1.008). mbrotli decodes faster than C in 91 of the 96 pairs. By
dataset, mbrotli leads Burli on Alice and cyclic Alice (median 1.21× and 1.23×
Burli's speed), is level on random input and structured binary (0.99-1.02×,
down to 0.89× at one quality), and trails on empty input (0.69×) and repeated
bytes (median 0.97×, 0.74× at one quality). Tiny text leads at the median
(1.10×) but stays Burli's where a first decode builds context-modelled tables
(down to 0.63×). This suite times only `decompress`; `decompress_to_slice`,
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
commit. The working tree's uncommitted changes are in the encoder only. The
run's [size manifest](decoder-comparison-2026-10-01/sizes.csv) is archived.

The sweep ran as four corpus shards on logical CPUs 8, 10, 12 and 14 while the
encoder sweep ran on CPUs 0, 2, 4 and 6: eight benchmark processes at once,
sharing the last-level cache, memory bandwidth and turbo budget. Absolute
timings are therefore below a single-core sweep; every decoder of a case ran in
the same process under the same load, so ratios are the comparable quantity.
Nothing else ran on the host during the sweep.

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
