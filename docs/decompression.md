# Decompression and limits

`Decompressor` owns reusable state. `decompress` returns a Vec,
`decompress_into` appends atomically, and `decompress_to_slice` writes into
caller storage. Sessions report consumed/produced counts; `reader` and `writer`
adapt synchronous I/O.

## Set limits for untrusted input

The default accepts one complete raw member and extended window declarations
up to 62 bits. **Numeric budgets are unlimited by default.** Configure them for
your application before decoding input you do not control:

```rust
use mbrotli::{DecodeLimits, DecoderConfig, Decompressor, WindowLimit};

fn decode_payload(input: &[u8]) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let limits = DecodeLimits::default()
        .with_max_input_bytes(Some(1 << 20))
        .with_max_output_bytes(Some(8 << 20))
        .with_max_workspace_bytes(Some(32 << 20));
    let config = DecoderConfig::default()
        .with_window_limit(WindowLimit::standard(24)?)
        .with_limits(limits);
    let mut decoder = Decompressor::new(config)?;
    Ok(decoder.decompress(input)?)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let payload = b"a payload from the network";
    let compressed = mbrotli::Compressor::new(Default::default())?.compress(payload)?;
    assert_eq!(decode_payload(&compressed)?, payload);
    Ok(())
}
```

The workspace budget excludes caller output and borrowed dictionaries; it is
not a process-memory limit. Keep the decoder across calls when reuse matters.

## Members, dictionaries and backends

`MemberMode::Concatenated` accepts successive raw
members. `DecodeDictionary` prepares decoding data without encoder indexes;
`PreparedDictionary` can also be borrowed. RAW dictionaries work in all profiles;
serialized/custom dictionaries require `experimental`.

Vec appends are rolled back on failure. The decoder specializes its command
loops and history copies for the selected CPU backend using safe
`fearless_simd` abstractions.

See [decoder mechanics](../architecture/decompressor.md) and
[compatibility limits](../architecture/decompressor-compatibility.md).

## Where to go next

| Task | Read |
| --- | --- |
| Decode chunks as they arrive | [Sans I/O decompression](sans-io-decompression.md) |
| Decode from a `Read` source or into a `Write` sink | [Read / Write I/O](io.md) |
| Decode a framing container | [Framing containers](frames.md) |
| Attach a dictionary | [Dictionaries and extended formats](dictionaries.md) |
