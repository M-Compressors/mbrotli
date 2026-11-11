# Configuration and features

Three things are configured separately: the **encoder** (how hard to search),
the **stream** (what you know about one input), and the **Cargo features**
(which codecs and adapters are compiled in). Decoder settings are covered in
[decompression and limits](decompression.md).

## Choose a quality first

`EncoderConfig::default()` uses **quality 11**, the most expensive search. Set
the quality explicitly for your workload:

```rust
use mbrotli::{Compressor, EncoderConfig, Quality};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = EncoderConfig::default().with_quality(Quality::Q5);
    let mut encoder = Compressor::new(config)?;
    let compressed = encoder.compress(b"configured payload")?;
    assert!(!compressed.is_empty());
    Ok(())
}
```

| Quality | Encoder | Search |
| --- | --- | --- |
| 0–1 | [Fast encoder](../architecture/fast-encoder.md) | Fragment-based fast paths with direct entropy coding |
| 2–9 | [Greedy encoder](../architecture/greedy-encoder.md) | Hash-table match search with match scoring |
| 10–11 | [High-quality encoder](../architecture/hq-encoder.md) | Tree search with command pricing and clustering |

Speed and size depend on your data. The
[benchmark pages](benchmarks/README.md) show both for every quality.

## Encoder settings

`EncoderConfig` holds settings shared by successive streams:

| Setting | Type | Behavior |
| --- | --- | --- |
| Quality | `Quality` | 0–11; default 11 |
| Window | `Window` | `Window::standard(bits)` for 10–24 bits; `Window::large(bits)` for 10–62 bits |
| Input block size | `BlockSize` / `BlockBits` | Automatic or explicit 16–24 bits |
| Data mode | `CompressionMode` | Generic, text, or font |
| Distance coding | `DistanceParams` | Validated postfix bits and direct distance groups |
| Literal contexts | `LiteralContextMode` | Controls literal context modelling |

Validated values reject out-of-range inputs. `Compressor::new` and
`reconfigure` check combinations, including Large Window's quality minimum.
The [capability table](#what-each-quality-supports) lists the minimum quality of each format.

`StreamConfig` carries the declared input size and logical stream offset.
Its default is unknown size and offset zero. For a complete known input,
use `StreamConfig::from(InputSize::Exact(input.len() as u64))`.

## What each quality supports

| Codec capability | Availability |
| --- | --- |
| Standard Brotli (RFC 7932) | Qualities 0–11 |
| Large Window Brotli | Qualities 3–11 |
| Prepared LZ77 prefix dictionaries | Qualities 5–11 |
| Serialized dictionaries and custom static dictionary encoding | `experimental`; qualities 5–11 |
| Headerless stream continuations | `experimental`; qualities 2–11 |
| Shared Brotli framed compressor, structured input and native sessions | `compression,experimental`; std or alloc |
| Framed encoder writer/reader adapters | `compression,experimental`; not available with `no_std` |
| Framed decoder, structured output and native events | `decompression,experimental`; std or alloc |
| Framed decoder event reader | `decompression,experimental`; not available with `no_std` |

Unsupported combinations return errors. External dictionary references require
the same dictionaries at the decoder. Large Window and shared-dictionary streams
require a decoder that supports the corresponding extension. See
[dictionaries and extended formats](dictionaries.md) for each format and
[compatibility and validation](correctness.md) for what is checked against C.

## Cargo features

The default feature set is `std`, `compression`, and `decompression`.

| Configuration | Dependency |
| --- | --- |
| Default std encoder + decoder | `mbrotli = "0.5.21"` |
| Encoder only | `mbrotli = { version = "0.5.21", default-features = false, features = ["std", "compression"] }` |
| Decoder only | `mbrotli = { version = "0.5.21", default-features = false, features = ["std", "decompression"] }` |
| Framing and experimental formats | `mbrotli = { version = "0.5.21", features = ["experimental"] }` |
| Alloc-backed codecs without std | `mbrotli = { version = "0.5.21", default-features = false, features = ["no_std", "compression", "decompression"] }` |

| Feature | Surface |
| --- | --- |
| `std` | `Read` / `Write` adapters and parallel compression |
| `compression`, `decompression` | One codec each; they compile independently |
| `no_std` | Alloc-backed build; takes precedence over `std` when both are enabled |
| `experimental` | Serialized shared dictionaries, custom static encoding, nonzero stream offsets, and framing. This API may change in a patch release |
| `diagnostics` | `PreparedDictionary::longest_match` prefix coverage diagnostic |
| `hotpath`, `hotpath-cpu`, `hotpath-alloc` | Optional profiling instrumentation |

`no_std` requires a global allocator. It excludes I/O adapters, parallel
compression, framed I/O adapters, and profiling, and uses compile-time SIMD
selection. Cargo features are additive: another dependency can re-enable a
codec or `std`. Leave `std` and `hotpath*` disabled throughout the dependency
graph for a std-free build.

See [codec features](../architecture/codec-features.md) and
[no_std support](../architecture/no-std.md) for the gates and their checks.
