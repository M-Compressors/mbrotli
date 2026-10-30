# Decompression comparison — 2026-10-30

[Benchmark index](README.md) · [Quality pages](decoders/README.md) · [CSV](decoder-comparison.csv)

The complete **384-case** run `dec-2026-10-30-amd` compares Google C Brotli 1.2.0,
the local mbrotli 0.5.19 checkout, Rust brotli 9.0.0 and Burli 0.3.3. All four
restore identical C-produced streams at source qualities q0–q11, generic mode
and window 22. SIMD Brotli re-exports the Rust Brotli decoder project and is omitted.

Across 96 corpus/quality pairs, mbrotli's median speed is **2.588× C**
and **1.006× Burli**. Its mean latency is lower than C in **80/96**
cases and lower than Burli in **53/96**. Its upper 95% mean-time bound is
below the peer's lower bound in **80/96** C comparisons and
**50/96** Burli comparisons. These are sweep counts, not universal leads.

## Final measurements

![Median decompression speed relative to C](decoders/charts/overview.svg)

| Source quality | Google C | mbrotli | Rust brotli | Burli | mbrotli / Burli |
| --- | ---: | ---: | ---: | ---: | ---: |
| [q0](decoders/q0.md) | 1.000× | 3.059× | 0.446× | 2.873× | 1.036× |
| [q1](decoders/q1.md) | 1.000× | 3.196× | 0.445× | 3.129× | 1.020× |
| [q2](decoders/q2.md) | 1.000× | 3.325× | 0.570× | 3.362× | 1.056× |
| [q3](decoders/q3.md) | 1.000× | 2.548× | 0.563× | 2.536× | 0.986× |
| [q4](decoders/q4.md) | 1.000× | 3.461× | 0.574× | 3.407× | 1.003× |
| [q5](decoders/q5.md) | 1.000× | 2.572× | 0.574× | 2.555× | 0.982× |
| [q6](decoders/q6.md) | 1.000× | 2.568× | 0.569× | 2.545× | 0.982× |
| [q7](decoders/q7.md) | 1.000× | 2.574× | 0.562× | 2.511× | 0.982× |
| [q8](decoders/q8.md) | 1.000× | 2.547× | 0.572× | 2.533× | 0.988× |
| [q9](decoders/q9.md) | 1.000× | 2.553× | 0.569× | 2.536× | 0.986× |
| [q10](decoders/q10.md) | 1.000× | 2.770× | 0.581× | 2.632× | 1.051× |
| [q11](decoders/q11.md) | 1.000× | 2.847× | 0.584× | 2.662× | 1.067× |

Library columns are medians of eight per-dataset C-time/library-time ratios.
The last column is the median of direct Burli-time/mbrotli-time ratios; it does
not divide C-relative medians. Overall medians use all 96 direct ratios. Empty
and tiny inputs have the same weight as larger inputs. Higher ratios are faster.

## Measurement contract

One process ran at a time on logical CPU 1 of an AMD Ryzen 9 7950X Linux VDS
with two KVM vCPUs. Encoding and decoding sweeps ran serially; no builds, tests,
fuzzers or other benchmarks ran concurrently. Rust 1.99.1 and GCC 15.2 used
ordinary release defaults, with runtime backend selection. Criterion used 20
samples, 1 s warmup and 3 s requested measurement per case.

The eight corpora are empty, tiny text, Alice, cyclic Alice at 1 MiB, structured
64 KiB binary, random bytes at 64 KiB/1 MiB and repeated `a` at 1 MiB. C prepares
96 streams once; all 384 decoder cases must restore the original bytes before
timing. Quality belongs to that source encoder, not to a decoder. Throughput
counts restored bytes, and compressed sizes are properties of the shared inputs.

Cold iterations include construction, allocation, decoding and disposal. C gets
the known output capacity and a freshly initialized buffer; Rust Vec APIs grow
their output. Rust Brotli includes native 4 KiB I/O adaptation. Burli decodes
every source quality. No decoder retains state between iterations.

## Provenance and limits

The [environment record](decoder-comparison-environment.json) identifies the
source hashes, lockfile, measured executable, commands and CSV. The matching
[size manifest](decoder-comparison-2026-10-30/sizes.csv) records the shared compressed/restored lengths.
This is one sweep on a virtual host with fixed implementation order.
Affinity does not control clocks, thermals, allocator effects or host scheduling;
sampling intervals do not cover every environmental bias. The measured cold APIs
do not cover retained state, streaming, dictionaries or streams from other producers.
mbrotli remains 3–8% slower than C on Alice at source qualities other than q10
(14% at q8) and 11–24% slower on tiny text at q5–q9, where fixed setup cost
dominates a 44-byte output.

## Reproduce

```sh
cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench decoders --locked --no-run
taskset -c 1 cargo bench --manifest-path benchmarks/comparison/Cargo.toml --bench decoders --locked -- --sample-size 20 --warm-up-time 1 --measurement-time 3 --noplot --save-baseline dec-2026-10-30-amd
python3 benchmarks/comparison/report.py --decoding --baseline dec-2026-10-30-amd --csv docs/benchmarks/decoder-comparison.csv
```

Use a fresh baseline for a new run and archive its size manifest immediately.
The measured run used the frozen executable recorded in the environment file.
[Benchmarking](../benchmarking.md) covers chart generation and separate API measurements.
