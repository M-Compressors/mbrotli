# Decoder comparison

[Benchmark index](../README.md)

Recorded run: **dec-2026-10-29-amd** (2026-10-29).
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
| [q4](q4.md) | 1.000× | 3.309× | 0.535× | 3.397× | 1.006× |
| [q2](q2.md) | 1.000× | 3.211× | 0.496× | 3.328× | 1.024× |
| [q1](q1.md) | 1.000× | 3.130× | 0.405× | 3.116× | 1.005× |
| [q0](q0.md) | 1.000× | 2.983× | 0.405× | 2.799× | 1.004× |
| [q11](q11.md) | 1.000× | 2.705× | 0.550× | 2.659× | 1.017× |
| [q10](q10.md) | 1.000× | 2.677× | 0.553× | 2.664× | 1.005× |
| [q5](q5.md) | 1.000× | 2.551× | 0.541× | 2.538× | 0.975× |
| [q7](q7.md) | 1.000× | 2.549× | 0.537× | 2.534× | 0.976× |
| [q6](q6.md) | 1.000× | 2.540× | 0.537× | 2.519× | 0.974× |
| [q3](q3.md) | 1.000× | 2.531× | 0.510× | 2.523× | 0.980× |
| [q8](q8.md) | 1.000× | 2.490× | 0.537× | 2.477× | 0.974× |
| [q9](q9.md) | 1.000× | 2.488× | 0.535× | 2.487× | 0.974× |

The last column takes the median of direct Burli time / mbrotli time ratios;
it does not divide the two medians relative to C.

Open a source quality for all datasets, compressed/restored byte counts,
mean latency, confidence bounds and throughput. Measurements include cold construction,
allocation, decoding and disposal. C receives the known output capacity; Rust brotli
includes its native 4 KiB I/O adapter. See the linked methodology for reproducible commands
and the limits of this single-host comparison.
