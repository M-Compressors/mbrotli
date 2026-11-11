# Buffers and memory reuse

Every call involves two kinds of memory: the **destination** you hand to the
codec, and the **workspace** the codec keeps for itself. You control both.

| You want to | Use |
| --- | --- |
| Get a fresh `Vec<u8>` | `compress` / `decompress` |
| Append to a Vec you already own | `compress_into` / `decompress_into` |
| Write into a fixed slice | `compress_to_slice` / `decompress_to_slice` |
| Cap what the codec keeps between calls | A [retention policy](#reusing-memory) |

## Output buffers

`compress` returns a new `Vec<u8>`. `compress_into` appends to the supplied
vector and returns the range containing the new stream; existing bytes remain
intact. On failure, the vector's length rolls back to its original value.

`compress_to_slice` returns the number of bytes written. Allocate a conservative
buffer using `Compressor::max_compressed_size`:

```rust
use mbrotli::{Compressor, EncoderConfig, Quality};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = b"data to compress";
    let mut encoder = Compressor::new(
        EncoderConfig::default().with_quality(Quality::Q5),
    )?;
    let bound = Compressor::max_compressed_size(input.len())?;
    let mut output = vec![0; bound];
    let written = encoder.compress_to_slice(input, &mut output)?;
    output.truncate(written);
    assert_eq!(output, encoder.compress(input)?);
    Ok(())
}
```

A slice exactly as long as the stream also suffices. An undersized slice returns
an error and may contain a partial prefix; retry the complete operation with a
larger slice. Capacity does not select a different encoding.

## Reusing memory

A compressor retains one encoder workspace. Compatible calls reset its logical
state and reuse its allocations. Incompatible resolved settings can rebuild that
workspace. Destination capacity is managed separately by the caller.

| Retention policy | Effect |
| --- | --- |
| `Aggressive` (default) | Keeps allocated buffers between operations |
| `CurrentConfig` | Releases incompatible storage when configuration changes |
| `Bounded { max_bytes }` | Releases retained storage when its accounting exceeds the ceiling |
| `ReleaseAll` | Releases storage after each operation |

Set the policy with `Compressor::builder(config).with_retention(policy).build()`.
Use `trim(policy)` for immediate cleanup. `retained_bytes()` reports owned
heap allocation sizes; it excludes caller buffers, shared dictionaries, and
allocator overhead. A retention ceiling is not a peak process-memory limit.

For simultaneous independent streams, use one compressor per worker.
`fork_empty()` copies configuration, backend, and retention settings without
copying the workspace. For one stream split across workers, see
[parallel compression](parallel.md).
