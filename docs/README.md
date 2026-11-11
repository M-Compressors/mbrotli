# Choose your API

Compression and decompression expose the same I/O shapes. Pick the row that
matches how your application already moves bytes, then follow its guide.
New to the crate? Start with [getting started](getting-started.md).

## Both codecs

| I/O shape | Compression | Decompression | Guide |
| --- | --- | --- | --- |
| Return a new `Vec<u8>` | `Compressor::compress` | `Decompressor::decompress` | [Getting started](getting-started.md) |
| Append to an existing Vec | `compress_into` | `decompress_into` | [Buffers and memory reuse](memory.md) |
| Write into a caller-owned slice | `compress_to_slice` | `decompress_to_slice` | [Buffers and memory reuse](memory.md#output-buffers) |
| Pull output through `std::io::Read` | `Compressor::reader` | `Decompressor::reader` | [Read / Write I/O](io.md) |
| Push input through `std::io::Write` | `Compressor::writer` | `Decompressor::writer` | [Read / Write I/O](io.md) |
| Drive input and output incrementally | `start` → `EncoderSession` | `start` → `DecoderSession` | Sans I/O [compression](sans-io-compression.md), [decompression](sans-io-decompression.md) |
| Same, with the session owning the codec | `into_session` → `EncoderSessionOwned` | `into_session` → `DecoderSessionOwned` | Sans I/O [compression](sans-io-compression.md), [decompression](sans-io-decompression.md) |

`Compressor` and `Decompressor` own reusable working state. Keep one alive
across payloads when allocation reuse matters.

## Parallel compression

`ParallelCompressor` is a separate execution strategy for compression: it
splits the input into independent segments and hands them to your executor as
tasks. The library does not create a thread pool. The output is one ordinary
Brotli stream, decoded by the ordinary `Decompressor`. Requires `std`.

| I/O shape | Entry point |
| --- | --- |
| Split one known input across your threads | `prepare_slice` / `prepare_source` → `ScopedParallelBatch` |
| Stream chunked input across your threads | `start` → `ParallelEncoderSession` + `ParallelTaskQueue` |
| Same, with the session owning the compressor | `into_session` → `ParallelEncoderSessionOwned` |
| Pull parallel output through `std::io::Read` | `reader` → `ParallelEncoderReader` + `ParallelTaskQueue` |
| Push input through `std::io::Write` across your threads | `writer` → `ParallelEncoderWriter` + `ParallelTaskQueue` |

See [parallel compression](parallel.md) for scoped threads, Rayon, budgets,
disk staging, and streaming.

## Guides by task

| Task | Read |
| --- | --- |
| Pick a quality, window, or Cargo features | [Configuration and features](configuration.md) |
| Control allocations and retained memory | [Buffers and memory reuse](memory.md) |
| Decode untrusted input with resource limits | [Decompression and limits](decompression.md) |
| Understand readers, writers, sessions, and `finish` | [Streaming and completion](streaming.md) |
| Connect readers and writers for every format | [Read / Write I/O](io.md) |
| Drive compression with caller buffers | [Sans I/O compression](sans-io-compression.md) |
| Decode arriving chunks and framed events | [Sans I/O decompression](sans-io-decompression.md) |
| Split a job across workers | [Parallel compression](parallel.md) |
| Write or decode framing containers | [Framing containers](frames.md) |
| Share a dictionary or use extended formats | [Dictionaries and extended formats](dictionaries.md) |
| Copy a complete program | [Examples](examples/README.md) |

## Errors

`ConfigError` covers configuration, `DictionaryError` covers dictionary
preparation, `EncodeError` covers compression, and `SizeOverflow` covers
size-bound arithmetic. I/O adapters return `std::io::Error`; writer finalization
preserves the writer in `FinishError`.

## Reference

- [API reference on docs.rs](https://docs.rs/mbrotli)
- [Compatibility and validation](correctness.md): what is byte-identical to
  Google Brotli, and how it is checked
- [Benchmark results](benchmarks/README.md) for every quality, with raw data
- [Architecture](../architecture/README.md): how the implementation works
- [Development](development.md) and [benchmarking](benchmarking.md) for
  contributors
