# Decoder comparison

[Benchmark index](../README.md)

Recorded run: **dec-2026-09-28** (2026-09-28).
[CSV](../decoder-comparison.csv) · [Environment](../decoder-comparison-environment.json) · [Methodology and limits](../decoder-comparison.md).

![Median decompression speed relative to C](charts/overview.svg)

Each value is the median of C mean time / decoder mean time across all 8 datasets,
equally weighted. Higher is faster; 1× matches C.
Qualities are ordered by mbrotli median speed / C. Medians do not imply statistical significance.

All four decoders restore identical C-generated streams. Source quality is an encoder setting,
not a decoder setting. Burli decodes q0–q11; SIMD Brotli shares Rust brotli's decoder and is omitted.
Compressed sizes and ratios are properties of those shared inputs, so there is no decoder size ranking.

| Source quality | Google C | mbrotli | Rust brotli | Burli | mbrotli / Burli |
| --- | ---: | ---: | ---: | ---: | ---: |
| [q2](q2.md) | 1.000× | 3.786× | 0.597× | 3.471× | 1.015× |
| [q4](q4.md) | 1.000× | 3.777× | 0.577× | 3.493× | 1.057× |
| [q0](q0.md) | 1.000× | 3.586× | 0.379× | 3.298× | 0.978× |
| [q1](q1.md) | 1.000× | 3.580× | 0.375× | 3.523× | 1.017× |
| [q3](q3.md) | 1.000× | 3.297× | 0.567× | 3.186× | 1.016× |
| [q9](q9.md) | 1.000× | 3.231× | 0.596× | 3.412× | 0.970× |
| [q6](q6.md) | 1.000× | 3.227× | 0.559× | 3.185× | 0.959× |
| [q5](q5.md) | 1.000× | 3.225× | 0.566× | 3.260× | 0.979× |
| [q11](q11.md) | 1.000× | 3.185× | 0.613× | 3.177× | 1.036× |
| [q8](q8.md) | 1.000× | 3.157× | 0.583× | 3.104× | 0.990× |
| [q10](q10.md) | 1.000× | 3.130× | 0.571× | 3.172× | 1.021× |
| [q7](q7.md) | 1.000× | 3.090× | 0.572× | 3.189× | 1.005× |

The last column takes the median of direct Burli time / mbrotli time ratios;
it does not divide the two medians relative to C.

Open a source quality for all datasets, compressed/restored byte counts,
mean latency, confidence bounds and throughput. Measurements include cold construction,
allocation, decoding and disposal. C receives the known output capacity; Rust brotli
includes its native 4 KiB I/O adapter. See the linked methodology for reproducible commands
and the limits of this single-host comparison.
