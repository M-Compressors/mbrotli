# Decoder comparison

[Benchmark index](../README.md)

Recorded run: **dec-2026-10-30-amd** (2026-10-30).
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
| [q4](q4.md) | 1.000× | 3.461× | 0.574× | 3.407× | 1.003× |
| [q2](q2.md) | 1.000× | 3.325× | 0.570× | 3.362× | 1.056× |
| [q1](q1.md) | 1.000× | 3.196× | 0.445× | 3.129× | 1.020× |
| [q0](q0.md) | 1.000× | 3.059× | 0.446× | 2.873× | 1.036× |
| [q11](q11.md) | 1.000× | 2.847× | 0.584× | 2.662× | 1.067× |
| [q10](q10.md) | 1.000× | 2.770× | 0.581× | 2.632× | 1.051× |
| [q7](q7.md) | 1.000× | 2.574× | 0.562× | 2.511× | 0.982× |
| [q5](q5.md) | 1.000× | 2.572× | 0.574× | 2.555× | 0.982× |
| [q6](q6.md) | 1.000× | 2.568× | 0.569× | 2.545× | 0.982× |
| [q9](q9.md) | 1.000× | 2.553× | 0.569× | 2.536× | 0.986× |
| [q3](q3.md) | 1.000× | 2.548× | 0.563× | 2.536× | 0.986× |
| [q8](q8.md) | 1.000× | 2.547× | 0.572× | 2.533× | 0.988× |

The last column takes the median of direct Burli time / mbrotli time ratios;
it does not divide the two medians relative to C.

Open a source quality for all datasets, compressed/restored byte counts,
mean latency, confidence bounds and throughput. Measurements include cold construction,
allocation, decoding and disposal. C receives the known output capacity; Rust brotli
includes its native 4 KiB I/O adapter. See the linked methodology for reproducible commands
and the limits of this single-host comparison.
