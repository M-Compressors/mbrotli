# Decoder comparison

[Benchmark index](../README.md)

Recorded run: **dec-2026-10-09** (2026-10-09).
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
| [q1](q1.md) | 1.000× | 3.782× | 0.369× | 3.793× | 1.003× |
| [q2](q2.md) | 1.000× | 3.682× | 0.586× | 3.674× | 1.021× |
| [q0](q0.md) | 1.000× | 3.674× | 0.359× | 3.174× | 0.989× |
| [q4](q4.md) | 1.000× | 3.626× | 0.561× | 3.698× | 0.996× |
| [q3](q3.md) | 1.000× | 3.315× | 0.555× | 3.320× | 0.998× |
| [q6](q6.md) | 1.000× | 3.248× | 0.603× | 3.273× | 0.975× |
| [q8](q8.md) | 1.000× | 3.239× | 0.577× | 3.153× | 1.026× |
| [q7](q7.md) | 1.000× | 3.220× | 0.597× | 3.196× | 1.017× |
| [q9](q9.md) | 1.000× | 3.200× | 0.589× | 3.170× | 1.014× |
| [q5](q5.md) | 1.000× | 3.178× | 0.616× | 3.075× | 0.987× |
| [q11](q11.md) | 1.000× | 3.158× | 0.582× | 3.226× | 0.979× |
| [q10](q10.md) | 1.000× | 3.112× | 0.599× | 3.173× | 0.979× |

The last column takes the median of direct Burli time / mbrotli time ratios;
it does not divide the two medians relative to C.

Open a source quality for all datasets, compressed/restored byte counts,
mean latency, confidence bounds and throughput. Measurements include cold construction,
allocation, decoding and disposal. C receives the known output capacity; Rust brotli
includes its native 4 KiB I/O adapter. See the linked methodology for reproducible commands
and the limits of this single-host comparison.
