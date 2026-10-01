# Decoder comparison

[Benchmark index](../README.md)

Recorded run: **dec-2026-10-01** (2026-10-01).
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
| [q4](q4.md) | 1.000× | 3.824× | 0.571× | 3.618× | 1.053× |
| [q0](q0.md) | 1.000× | 3.770× | 0.363× | 3.501× | 0.972× |
| [q2](q2.md) | 1.000× | 3.631× | 0.580× | 3.531× | 1.037× |
| [q1](q1.md) | 1.000× | 3.567× | 0.338× | 3.476× | 0.995× |
| [q8](q8.md) | 1.000× | 3.198× | 0.537× | 3.214× | 0.956× |
| [q10](q10.md) | 1.000× | 3.174× | 0.571× | 3.159× | 1.011× |
| [q6](q6.md) | 1.000× | 3.163× | 0.524× | 3.213× | 0.991× |
| [q7](q7.md) | 1.000× | 3.129× | 0.587× | 3.165× | 0.990× |
| [q9](q9.md) | 1.000× | 3.118× | 0.564× | 3.050× | 0.981× |
| [q3](q3.md) | 1.000× | 3.102× | 0.566× | 3.150× | 0.985× |
| [q11](q11.md) | 1.000× | 3.089× | 0.563× | 3.073× | 1.033× |
| [q5](q5.md) | 1.000× | 3.083× | 0.604× | 3.099× | 0.975× |

The last column takes the median of direct Burli time / mbrotli time ratios;
it does not divide the two medians relative to C.

Open a source quality for all datasets, compressed/restored byte counts,
mean latency, confidence bounds and throughput. Measurements include cold construction,
allocation, decoding and disposal. C receives the known output capacity; Rust brotli
includes its native 4 KiB I/O adapter. See the linked methodology for reproducible commands
and the limits of this single-host comparison.
