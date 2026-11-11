# Streaming and completion

Use streaming when the payload does not fit in memory, arrives in pieces, or
must leave before the input ends. There are three shapes, and they drive the
same state machine:

| Shape | You call | The library does | Recipes |
| --- | --- | --- | --- |
| Reader | `read` on the adapter | Pulls source bytes and yields transformed bytes | [Read / Write I/O](io.md) |
| Writer | `write_all`, then `finish` | Pushes transformed bytes into your sink | [Read / Write I/O](io.md) |
| Session | `process` with your own buffers | No I/O; reports consumed and produced counts | Sans I/O [compression](sans-io-compression.md) and [decompression](sans-io-decompression.md) |

Readers and writers require std. Sessions also work with `no_std` and `alloc`,
and fit async runtimes and event loops.

## Readers and writers

`reader(source, stream)` consumes source bytes and yields transformed bytes
through `Read`. `writer(sink, stream)` accepts source bytes through `Write`
and delivers transformed bytes to the sink. Compression takes plain input;
decompression takes compressed input. Both adapter families require std APIs.

```rust
use mbrotli::{Compressor, EncoderConfig, InputSize, Quality};
use std::io::Write;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let payload = b"streamed payload";
    let mut encoder = Compressor::new(
        EncoderConfig::default().with_quality(Quality::Q5),
    )?;
    let stream = InputSize::Exact(payload.len() as u64).into();
    let mut writer = encoder.writer(Vec::new(), stream)?;
    writer.write_all(payload)?;
    let compressed = writer.finish().map_err(mbrotli::io::FinishError::into_error)?;
    assert!(!compressed.is_empty());
    Ok(())
}
```

For a decoder reader, pass compressed input and `DecodeStreamConfig::default()`,
then read the restored bytes to EOF. `into_parts()` recovers any reader read-ahead.
A decoder writer must also be finished: finalization reports incomplete or invalid
input. In a direct decoder session, declare final input with `DecodeOperation::Finish`.

A writer borrows the compressor and owns its sink. Use `write_all` for input,
`flush` for an intermediate decoding boundary, and `finish` to terminate the
stream. Frequent flushes add block boundaries and can increase output size.

`try_finish(&mut self)` supports retrying finalization after an I/O error.
Consuming `finish` returns the sink on success; `FinishError` retains the writer
on failure. Use `into_parts()` to recover both the error and writer for retry.
`into_error()` discards the writer.

The writer retains pending output across short writes and sink errors. An input
write can succeed after accepting bytes even if delivery then fails; that
delivery error is reported on a subsequent drain. Continue according to the
returned byte counts rather than replaying accepted input. Dropping a writer
performs no finalization.

A reader owns its input source and borrows the compressor. Read until EOF to
receive the complete compressed stream. Dropping it early abandons that stream.

## Sessions

For direct buffer control, `start` creates an `EncoderSession`.
Call `process` with input, output, and an `Operation`:

| Operation/status | Meaning |
| --- | --- |
| `Operation::Process` | Accept input without ending the stream |
| `Operation::Flush` | Emit accepted input and a decoding boundary |
| `Operation::Finish` | End the stream after the supplied input |
| `EncoderStatus::NeedsInput` | Supply more input or an explicit flush/finish |
| `EncoderStatus::NeedsOutput` | Supply output space and continue with unconsumed input |
| `EncoderStatus::Finished` | All final output has been delivered |

Use `Progress` to advance by the reported consumed and written counts.
Finish can require several calls when output buffers are small. Sessions retain
their own pending data and do not retain the caller's slices.

A dropped unfinished session invalidates partial encoder state, allowing a fresh
stream on the next call. A session discarded with `mem::forget` requires
`Compressor::recover()` before reuse.
