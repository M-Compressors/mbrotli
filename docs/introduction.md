# Brotli in safe Rust

<div class="book-hero">
<div class="eyebrow">MBROTLI · THE GUIDE</div>
<p class="headline">Less bytes.<br>More Rust.</p>
<p class="intro">Compress a payload. Reuse your workspace. Scale across cores.
A native Brotli encoder and decoder, with buffers and scheduling under your control.</p>
<div class="book-actions">
<a class="primary" href="getting-started.md">Get started →</a>
<a href="examples/README.md">Explore examples</a>
<a href="https://docs.rs/mbrotli">API reference ↗</a>
</div>
</div>

## Choose your path

| You want to… | Start here |
| :--- | :--- |
| Compress and decompress your first payload | [Getting started](getting-started.md) |
| Connect files, buffers, and incremental sessions | [API guide](README.md) |
| Feed compression or decompression one chunk at a time | [Sans I/O compression](sans-io-compression.md) · [decompression](sans-io-decompression.md) |
| Connect raw, parallel, and framed streams to I/O | [Read / Write I/O](io.md) |
| Compress one input across CPU cores | [Parallel compression](parallel.md) |
| Package several resources in a container | [Framing containers](frames.md) · experimental |
| Understand ownership, dispatch, and state machines | [Architecture](../architecture/README.md) |
| Compare speed **and** output size | [Benchmarks](benchmarks/README.md) |

## Built for real pipelines

**Safe implementation.** The main crate forbids `unsafe` in production code.
SIMD acceleration uses `fearless_simd`. The encoder and decoder are native Rust;
Google's C implementation is an oracle for development and benchmarks.

**Reusable state.** Keep a compressor or decompressor across requests. Choose
owned output, borrowed buffers, `Read` / `Write` adapters, or sans-I/O sessions.

**Your scheduler.** Parallel compression returns tasks for scoped threads,
Rayon, or your own executor. The library does not create a thread pool.

**Documented mechanics.** Follow the same implementation from public API to
private state machines in the [architecture specifications](../architecture/README.md).
All guides, diagrams, benchmark charts, and raw measurements are published from
the repository's `docs/` and `architecture/` sources.

## Before you start

Use Rust **1.89 or later**. The default features enable `std`, compression,
and decompression. Framing requires `experimental`; its APIs may change in a
patch release. See [compatibility and correctness](correctness.md) for the
scope of C byte-identity checks and extended-format validation.
