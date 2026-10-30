# Compression comparison — 2026-10-30

[Benchmark index](README.md) · [Quality pages](encoders/README.md) · [CSV](encoder-comparison.csv)

The complete **432-case** run `enc-2026-10-30-amd` compares Google C Brotli 1.2.0,
the optimized local mbrotli 0.5.19 checkout, Rust brotli 9.0.0, SIMD Brotli 10.0.1
and Burli 0.3.3. Source and executable identities are in the
[environment record](encoder-comparison-environment.json); the matching
[size manifest](encoder-comparison-2026-10-30/sizes.csv) is retained with this run.

## Final measurements

![Median compression speed and size relative to C](encoders/charts/overview.svg)

Across all 96 matching corpus/quality pairs, mbrotli's median C-time/mbrotli-time
ratio is **1.099×**. Its mean is lower than C in **67/96** cases
and lower than every supported peer in **54/96**. In **66/96** cases,
mbrotli's upper 95% mean-time bound is below C's lower bound; the corresponding
count against every peer is **53/96**. These counts describe this sweep,
not a universal or workload-weighted performance guarantee.

mbrotli is above C at **12/12** per-quality corpus medians. Each median gives
the eight datasets equal weight, including empty and tiny input. It is computed
from per-dataset C mean time / library mean time, not from median sample times.

| Quality | Google C | mbrotli | Rust brotli | SIMD Brotli | Burli | mbrotli output / C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [q0](encoders/q0.md) | 1.000× | 1.349× | 0.090× | 0.100× | 2.011× | 1.000× |
| [q1](encoders/q1.md) | 1.000× | 1.123× | 0.107× | 0.141× | 0.825× | 1.000× |
| [q2](encoders/q2.md) | 1.000× | 1.020× | 0.355× | 0.336× | 0.793× | 1.000× |
| [q3](encoders/q3.md) | 1.000× | 1.089× | 0.409× | 0.401× | 0.952× | 1.000× |
| [q4](encoders/q4.md) | 1.000× | 1.183× | 0.529× | 0.488× | 1.201× | 1.000× |
| [q5](encoders/q5.md) | 1.000× | 1.017× | 0.442× | 0.355× | 0.942× | 1.000× |
| [q6](encoders/q6.md) | 1.000× | 1.008× | 0.404× | 0.344× | — | 1.000× |
| [q7](encoders/q7.md) | 1.000× | 1.004× | 0.360× | 0.331× | — | 1.000× |
| [q8](encoders/q8.md) | 1.000× | 1.022× | 0.291× | 0.285× | — | 1.000× |
| [q9](encoders/q9.md) | 1.000× | 4.323× | 0.828× | 1.681× | — | 1.000× |
| [q10](encoders/q10.md) | 1.000× | 1.243× | 0.839× | 0.899× | — | 1.000× |
| [q11](encoders/q11.md) | 1.000× | 1.493× | 0.834× | 0.906× | — | 1.000× |

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
taskset -c 1 cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench implementations --locked -- --sample-size 20 --warm-up-time 1 --measurement-time 3 --noplot --save-baseline enc-2026-10-30-amd
python3 benchmarks/comparison/report.py --baseline enc-2026-10-30-amd --csv docs/benchmarks/encoder-comparison.csv
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
Against the 2026-10-29 sweep, C itself ran 5–22% faster on 64 KiB binary and
random input at q2–q4 while mbrotli moved by at most 2%, which accounts for
most of the lower overall median.
