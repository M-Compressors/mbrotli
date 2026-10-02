# Decompression comparison — 2026-10-02

[Benchmark index](README.md) · [All quality pages](decoders/README.md) ·
[Published CSV](decoder-comparison.csv)

The published 384 rows cover four decoders on eight identical C-produced inputs
at each source quality, recorded as `dec-2026-10-02` with Rust brotli 9.0.0
(decoder `brotli-decompressor` 6.0.1) and Burli 0.3.3.
mbrotli's median speed relative to Burli is **0.999×**
across all 96 corpus/quality pairs; Burli is faster in 48 of them. Empty and tiny
inputs have the same weight as large inputs. Per-workload results include cases
where mbrotli is slower.

| Source quality | Google C | mbrotli | Rust brotli | Burli | mbrotli / Burli |
| --- | ---: | ---: | ---: | ---: | ---: |
| q0 | 1.000× | 3.471× | 0.342× | 3.228× | 0.971× |
| q1 | 1.000× | 3.644× | 0.341× | 3.431× | 1.009× |
| q2 | 1.000× | 3.792× | 0.539× | 3.748× | 1.023× |
| q3 | 1.000× | 2.978× | 0.556× | 3.123× | 0.970× |
| q4 | 1.000× | 3.946× | 0.531× | 3.962× | 1.022× |
| q5 | 1.000× | 3.177× | 0.527× | 3.126× | 1.011× |
| q6 | 1.000× | 3.120× | 0.579× | 3.114× | 1.000× |
| q7 | 1.000× | 3.325× | 0.559× | 3.322× | 0.999× |
| q8 | 1.000× | 3.232× | 0.529× | 3.166× | 0.968× |
| q9 | 1.000× | 3.201× | 0.534× | 3.291× | 0.984× |
| q10 | 1.000× | 3.199× | 0.529× | 3.177× | 1.013× |
| q11 | 1.000× | 3.322× | 0.573× | 3.272× | 1.019× |

Each library column is the median of eight C mean time / decoder mean time
ratios. The last column uses direct Burli time / mbrotli time ratios. The overall
value takes the median of all 96 direct ratios, not an average of quality medians.
Higher is faster; medians do not establish statistical significance.

mbrotli decodes faster than C in 89 of the 96 pairs. By dataset, mbrotli leads
Burli on Alice and cyclic Alice (median 1.16× and 1.19× Burli's speed), is level
on random input, structured binary and repeated bytes (0.96-1.01×, down to 0.70×
at one quality), and trails on empty input (0.73×). Tiny text leads at the
median (1.13×) but stays Burli's where a first decode builds context-modelled
tables (down to 0.60×). This suite times only `decompress`;
`decompress_to_slice`, `decompress_to_uninit` and the streaming sessions are
measured by the root `decompress` benchmark.

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
commit; the decoder sources are those of that commit. The run's
[size manifest](decoder-comparison-2026-10-02/sizes.csv) is archived.

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
