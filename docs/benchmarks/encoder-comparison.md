# Compression comparison — 2026-10-29

[Benchmark index](README.md) · [Quality pages](encoders/README.md) · [CSV](encoder-comparison.csv)

The complete **432-case** run `enc-2026-10-29-amd` compares Google C Brotli 1.2.0,
the optimized local mbrotli 0.5.17 checkout, Rust brotli 9.0.0, SIMD Brotli 10.0.1
and Burli 0.3.3. Source and executable identities are in the
[environment record](encoder-comparison-environment.json); the matching
[size manifest](encoder-comparison-2026-10-29/sizes.csv) is retained with this run.

## Final measurements

![Median compression speed and size relative to C](encoders/charts/overview.svg)

Across all 96 matching corpus/quality pairs, mbrotli's median C-time/mbrotli-time
ratio is **1.146×**. Its mean is lower than C in **68/96** cases
and lower than every supported peer in **54/96**. In **64/96** cases,
mbrotli's upper 95% mean-time bound is below C's lower bound; the corresponding
count against every peer is **50/96**. These counts describe this sweep,
not a universal or workload-weighted performance guarantee.

mbrotli is above C at **10/12** per-quality corpus medians. Each median gives
the eight datasets equal weight, including empty and tiny input. It is computed
from per-dataset C mean time / library mean time, not from median sample times.

| Quality | Google C | mbrotli | Rust brotli | SIMD Brotli | Burli | mbrotli output / C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [q0](encoders/q0.md) | 1.000× | 1.377× | 0.092× | 0.099× | 1.998× | 1.000× |
| [q1](encoders/q1.md) | 1.000× | 1.111× | 0.111× | 0.145× | 0.825× | 1.000× |
| [q2](encoders/q2.md) | 1.000× | 1.191× | 0.361× | 0.343× | 0.851× | 1.000× |
| [q3](encoders/q3.md) | 1.000× | 1.225× | 0.427× | 0.420× | 0.985× | 1.000× |
| [q4](encoders/q4.md) | 1.000× | 1.306× | 0.521× | 0.479× | 1.276× | 1.000× |
| [q5](encoders/q5.md) | 1.000× | 1.020× | 0.431× | 0.351× | 0.937× | 1.000× |
| [q6](encoders/q6.md) | 1.000× | 0.996× | 0.411× | 0.340× | — | 1.000× |
| [q7](encoders/q7.md) | 1.000× | 0.978× | 0.360× | 0.330× | — | 1.000× |
| [q8](encoders/q8.md) | 1.000× | 1.030× | 0.295× | 0.282× | — | 1.000× |
| [q9](encoders/q9.md) | 1.000× | 4.248× | 0.836× | 1.652× | — | 1.000× |
| [q10](encoders/q10.md) | 1.000× | 1.255× | 0.835× | 0.898× | — | 1.000× |
| [q11](encoders/q11.md) | 1.000× | 1.516× | 0.826× | 0.926× | — | 1.000× |

mbrotli and C have equal compressed lengths in **96/96** matching cases.
This suite validates round trips through C, not compressed byte identity.
Burli encodes only q0–q5; equal quality numbers do not imply equal output size.

## Measurement contract

One benchmark process ran at a time, pinned to logical CPU 1 on an AMD
Ryzen 9 7950X Linux VDS exposing two KVM vCPUs. Neither builds, tests, fuzzers
nor another benchmark ran concurrently. Rust 1.99.1 and GCC 15.2 used ordinary
release defaults, with runtime backend selection and no profiling or native-CPU
flags. Criterion collected 20 samples after 1 s warmup, requesting 3 s of
measurement per case; slow cases may exceed that duration.

Generic mode, window 22, complete known input, no dictionaries or explicit flushes.
Cold iterations include construction, allocation, encoding and disposal. C's
one-shot wrapper includes initialized output allocation and native output rewrites;
Rust Brotli and SIMD Brotli include their native 4 KiB I/O adapters. No library
retains workspace. Corpus construction and validation of all 432 outputs finish
before timing. Inputs are empty, 44-byte text, Alice (152,089 bytes), cyclic Alice
at 1 MiB, structured 64 KiB binary, deterministic random 64 KiB/1 MiB and repeated
`a` at 1 MiB. All means, confidence bounds and byte counts remain in the quality pages.

## Reproduce

```sh
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --locked --no-run
taskset -c 1 cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --locked -- --sample-size 20 --warm-up-time 1 --measurement-time 3 --noplot --save-baseline enc-2026-10-29-amd
python3 benchmarks/comparison/report.py --baseline enc-2026-10-29-amd --csv docs/benchmarks/encoder-comparison.csv
```

Use a fresh baseline name for a new run. The measured run used the frozen
executable recorded in the environment file, directly after its completed build.
Archive `sizes.csv` immediately with its corresponding baseline. The
[benchmark guide](../benchmarking.md) gives chart and page-generation commands.

## Interpretation limits

This is one serial sweep on a virtual host, with fixed implementation order.
CPU affinity does not control host scheduling, clocks, thermal state or allocator
page reuse. Sampling intervals do not include every source of environmental bias.
Equal corpus weight is not a production workload distribution. These results
cover cold serial APIs; streaming, retained workspace, parallel execution and
dictionaries require their separate API benchmarks. Earlier Intel and intermediate
AMD sweeps are not paired before/after controls for this measured source.
