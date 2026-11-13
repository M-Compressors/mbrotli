# Brotli compression and decompression in safe Rust

<div class="landing">
<p class="lede">mbrotli is a port of Google's Brotli encoder with a Rust-native API, plus a native Rust decoder. Reuse working memory between payloads, plug into <code>Read</code> and <code>Write</code>, drive either codec with your own buffers, and schedule parallel compression on your own threads.</p>
<div class="actions">
<a class="primary" href="getting-started.md">Get started</a>
<a href="README.md">Choose your API</a>
<a href="https://docs.rs/mbrotli">API reference on docs.rs</a>
</div>
</div>

## A round trip

```toml
[dependencies]
mbrotli = "0.5.22"
```

```rust
use mbrotli::{Compressor, Decompressor, EncoderConfig, Quality};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = "hello, smaller world! ".repeat(1000);
    let mut encoder = Compressor::new(EncoderConfig::default().with_quality(Quality::Q5))?;
    let compressed = encoder.compress(input.as_bytes())?;

    let mut decoder = Decompressor::new(Default::default())?;
    assert_eq!(decoder.decompress(&compressed)?, input.as_bytes());
    Ok(())
}
```

Requires Rust **1.89 or later**. [Getting started](getting-started.md) continues
from here with memory reuse, streaming and feature selection.

## Pick a quality

Quality is the first decision: the default is **11**, the slowest and smallest.
Each bar is the compressed size of the 211 MB Silesia corpus against its
original size.

<div class="ladder">
<table>
<thead>
<tr><th>Quality</th><th>Compressed size</th><th class="num">Compress</th><th class="num wide">Decompress</th></tr>
</thead>
<tbody>
<tr><td>0</td><td class="size"><span class="track"><span class="fill" style="width: 37.02%">37.0%</span></span></td><td class="num">549 MB/s</td><td class="num wide">585 MB/s</td></tr>
<tr><td>2</td><td class="size"><span class="track"><span class="fill" style="width: 32.12%">32.1%</span></span></td><td class="num">186 MB/s</td><td class="num wide">703 MB/s</td></tr>
<tr><td>5</td><td class="size"><span class="track"><span class="fill" style="width: 28.10%">28.1%</span></span></td><td class="num">78.2 MB/s</td><td class="num wide">788 MB/s</td></tr>
<tr><td>8</td><td class="size"><span class="track"><span class="fill" style="width: 26.96%">27.0%</span></span></td><td class="num">21.8 MB/s</td><td class="num wide">862 MB/s</td></tr>
<tr><td>11</td><td class="size"><span class="track"><span class="fill" style="width: 23.83%">23.8%</span></span></td><td class="num">1.23 MB/s</td><td class="num wide">713 MB/s</td></tr>
</tbody>
</table>
</div>

<p class="note">mbrotli 0.5.20 in lzbench 2.4.1 on one thread of an AMD Ryzen 9 7950X VDS. Your data and machine will differ.</p>

See the [lzbench run](benchmarks/lzbench-2026-11-08.md) for the command and raw
output, and [benchmark results](benchmarks/README.md) for every quality against
Google's C implementation and other Rust crates.

## Find your path

<div class="paths">
<a href="getting-started.md"><strong>First round trip</strong><span>Install, compress, decompress and reuse a codec.</span></a>
<a href="README.md"><strong>Choose your API</strong><span>Every entry point for both codecs in one table.</span></a>
<a href="configuration.md"><strong>Configuration and features</strong><span>Quality, window, Cargo features and <code>no_std</code>.</span></a>
<a href="decompression.md"><strong>Decode untrusted input</strong><span>Input, output and workspace budgets.</span></a>
<a href="streaming.md"><strong>Streaming</strong><span>Readers, writers, sans-I/O sessions and <code>finish</code>.</span></a>
<a href="parallel.md"><strong>Parallel compression</strong><span>One input across scoped threads, Rayon or your executor.</span></a>
<a href="frames.md"><strong>Framing containers <span class="tag">experimental</span></strong><span>Several resources and metadata in one container.</span></a>
<a href="../architecture/README.md"><strong>How it works</strong><span>Ownership, dispatch and state machines, with diagrams.</span></a>
</div>

## What you can rely on

- **Safe implementation, not a C wrapper.** Production code forbids `unsafe`;
  SIMD goes through `fearless_simd`. Google's C library is only a test and
  benchmark oracle.
- **Reference-compatible output.** Qualities 0–11 are compared byte for byte
  with Google Brotli under equivalent streaming settings. See
  [what is claimed and how it is checked](correctness.md).
- **No hidden I/O or threads.** Sessions touch only the buffers you pass in,
  and parallel compression hands tasks to your scheduler. The library does not
  create a thread pool.
- **Reusable state.** A codec keeps its workspace between payloads, under a
  [retention policy](memory.md#reusing-memory) you choose.

Framing and other formats behind the `experimental` feature may change in a
patch release.
