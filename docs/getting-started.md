# Getting started

Build a complete round trip, then choose the API that fits your application.
Requires **Rust 1.89+**.

## Install

```sh
cargo new brotli-demo
cd brotli-demo
cargo add mbrotli@0.5.21
```

Or add this to `Cargo.toml`:

```toml
[dependencies]
mbrotli = "0.5.21"
```

## Compress and decompress

Replace `src/main.rs` with this complete program:

```rust
use mbrotli::{Compressor, Decompressor, EncoderConfig, Quality};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = "hello, smaller world! ".repeat(1000);
    let config = EncoderConfig::default().with_quality(Quality::Q5);
    let mut encoder = Compressor::new(config)?;
    let compressed = encoder.compress(input.as_bytes())?;

    let mut decoder = Decompressor::new(Default::default())?;
    let restored = decoder.decompress(&compressed)?;
    assert_eq!(restored, input.as_bytes());

    println!("{} input bytes → {} compressed bytes", input.len(), compressed.len());
    Ok(())
}
```

```sh
cargo run --release
```

Choose the quality explicitly: the default is **Q11**. Higher quality spends
more CPU searching for compression opportunities. Compare speed and output size
on your data; [the benchmark pages](benchmarks/README.md) show how results vary
with input and quality.

## Reuse the workspace and output

A codec retains working memory between calls. `compress_into` appends a stream
and returns its range; clear the destination when you want to reuse it for a
new payload.

```rust
use mbrotli::{Compressor, Decompressor, EncoderConfig, Quality};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut encoder = Compressor::new(
        EncoderConfig::default().with_quality(Quality::Q5),
    )?;
    let mut decoder = Decompressor::new(Default::default())?;
    let mut output = Vec::new();

    for payload in [b"first message".as_slice(), b"second message".as_slice()] {
        output.clear();
        let stream = encoder.compress_into(payload, &mut output)?;
        assert_eq!(decoder.decompress(&output[stream])?, payload);
    }
    Ok(())
}
```

See [retention policies](memory.md#reusing-memory) to control which workspace
allocations remain after an operation. Caller output capacity is separate.

## Stream through `Write`

Write plain input into the adapter, then call `finish` to obtain a complete
Brotli stream. Dropping the writer does not finalize it.

```rust
use mbrotli::{Compressor, Decompressor, EncoderConfig, InputSize, Quality};
use std::io::Write;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = b"a payload arriving in two writes";
    let mut encoder = Compressor::new(
        EncoderConfig::default().with_quality(Quality::Q5),
    )?;
    let stream = InputSize::Exact(input.len() as u64).into();
    let mut writer = encoder.writer(Vec::new(), stream)?;
    writer.write_all(&input[..10])?;
    writer.write_all(&input[10..])?;
    let compressed = writer.finish().map_err(mbrotli::io::FinishError::into_error)?;

    let mut decoder = Decompressor::new(Default::default())?;
    assert_eq!(decoder.decompress(&compressed)?, input);
    Ok(())
}
```

For a retryable sink failure, `FinishError::into_parts` returns the error and
writer. `into_error` discards the writer, as this in-memory example does.
The [streaming guide](streaming.md) explains completion,
backpressure, reader read-ahead, and direct sessions.

## Choose features

The default features enable `std` and both codecs. To build only one codec,
drop std, or enable framing and other experimental formats, see
[Cargo features](configuration.md#cargo-features).

## Next steps

- [Sans I/O compression](sans-io-compression.md) and [decompression](sans-io-decompression.md): caller buffers, progress counts, and completion.
- [Read / Write I/O](io.md): readers and writers for raw, parallel, and framed streams.
- [Parallel compression](parallel.md): scoped threads, Rayon, files, and streaming.
- [Framing containers](frames.md): multiple resources, metadata, and indexed reads.
- [Choose your API](README.md): every entry point for both codecs, with its guide.
- [Configuration and features](configuration.md): quality, window, and Cargo features.
- [Decompression and limits](decompression.md): budgets for untrusted input.
- [Examples](examples/README.md): pick a recipe and run the repository examples.
