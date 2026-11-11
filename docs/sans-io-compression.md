# Sans I/O compression

Use a session when your application owns the input/output buffers and decides
when more bytes are available. Sessions perform no I/O. This works in a blocking
loop, an async task, or a custom event loop without an I/O adapter.

| Output format | Session entry point | Scheduling |
| --- | --- | --- |
| Raw Brotli | `Compressor::start(stream)` | Call `process` yourself |
| One raw stream encoded across workers | `ParallelCompressor::start(window)` | Drive `process` and run its task queue |
| Framed resources · experimental | `FramedCompressor::start(stream)` | Drain container output, drive resource guards, finish container |

For transport integration, see [Read / Write I/O](io.md). For the inverse
operation, see [Sans I/O decompression](sans-io-decompression.md).

## Drive a raw encoder

Supply chunks with `Operation::Process`. After the last chunk, call `Finish`
until `EncoderStatus::Finished`. An empty input passed with `Process` is not EOF.
The deliberately small output buffer below forces repeated output drains.

```rust
use mbrotli::{
    Compressor, Decompressor, EncoderConfig, EncoderStatus, InputSize, Operation, Quality,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = b"incremental encoding with tiny buffers\n".repeat(100);
    let config = EncoderConfig::default().with_quality(Quality::Q5);
    let mut encoder = Compressor::new(config)?;
    let mut compressed = Vec::new();
    let mut output = [0; 11];
    {
        let mut session = encoder.start(InputSize::Exact(input.len() as u64).into())?;
        for chunk in input.chunks(7) {
            let mut remaining = chunk;
            loop {
                let progress = session.process(remaining, &mut output, Operation::Process)?;
                remaining = &remaining[progress.consumed..];
                compressed.extend_from_slice(&output[..progress.produced]);
                if progress.status == EncoderStatus::NeedsInput {
                    assert!(remaining.is_empty());
                    break;
                }
            }
        }
        loop {
            let progress = session.process(&[], &mut output, Operation::Finish)?;
            compressed.extend_from_slice(&output[..progress.produced]);
            if progress.status == EncoderStatus::Finished {
                break;
            }
        }
    }
    // Exact input size, offset zero, and no flushes preserve one-shot bytes.
    assert_eq!(compressed, encoder.compress(&input)?);
    let mut decoder = Decompressor::new(Default::default())?;
    assert_eq!(decoder.decompress(&compressed)?, input);
    Ok(())
}
```

Always advance input by `consumed` and publish only `output[..produced]` before
handling status. `NeedsOutput` requires output space and the unconsumed input
suffix; reaching the end of the current input slice alone does not finish the
stream.

## Flush and finish are different

`Operation::Flush` makes accepted bytes decodable without ending the stream.
Drain it to `NeedsInput` before changing operation or supplying new input.
Flush boundaries can change output size and bytes. `Finish` ends the stream;
while retrying it, keep the same operation and exact unconsumed input suffix.

Use `InputSize::Exact` when the total input size is known. Otherwise use the
default unknown size; the encoder infers its size hint when it first encodes.
See [stream scheduling and identity](correctness.md#output-compatibility).

## Drive parallel input

`ParallelCompressor::start(window)` returns `(session, queue)`. Keep workers
running the queue while you feed input and drain output. The session's `process`
does not block: `ParallelEncoderStatus::Pending` means progress depends on tasks.
Call `session.wait()` with independently runnable workers, or execute queued tasks
yourself before waiting on a single thread.

The [complete Sans I/O parallel example](parallel.md#streaming-input) handles
all statuses and source chunks. Its window bounds queued, running, and
not-yet-delivered segments. Without flushes, output matches a batch over the same
input and segment configuration. See [parallel session mechanics](../architecture/parallel-stream.md).

## Drive a framed encoder

Enable `experimental`. Container `process` takes an output buffer and a
`FramedEncodeOperation`; resource `process` takes payload, output, and an ordinary
`Operation`. Finish the resource before finishing the container.

```rust
use mbrotli::framing::{
    FramedCompressor, FramedDecompressor, FramedEncodeConfig,
    FramedEncodeOperation, FramedEncoderStatus, FramingConfig,
};
use mbrotli::{EncoderConfig, Operation, Quality};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = b"framed incremental payload\n".repeat(20);
    let config = FramedEncodeConfig::default()
        .with_encoder_config(EncoderConfig::default().with_quality(Quality::Q5))
        .with_framing_config(FramingConfig { chunk_bytes: 32, ..Default::default() });
    let mut encoder = FramedCompressor::new(config)?;
    let mut session = encoder.start(Default::default())?;
    let mut buffer = [0; 13];
    let mut container = Vec::new();
    // Drain the main header before accepting a resource command.
    loop {
        let progress = session.process(&mut buffer, FramedEncodeOperation::Process)?;
        container.extend_from_slice(&buffer[..progress.produced]);
        if progress.status == FramedEncoderStatus::NeedsInput {
            break;
        }
    }
    {
        let mut resource = session.resource(Default::default(), Default::default())?;
        let mut chunks = input.chunks(9).peekable();
        while let Some(chunk) = chunks.next() {
            let operation = if chunks.peek().is_none() {
                Operation::Finish
            } else {
                Operation::Process
            };
            let mut remaining = chunk;
            loop {
                let progress = resource.process(remaining, &mut buffer, operation)?;
                remaining = &remaining[progress.consumed..];
                container.extend_from_slice(&buffer[..progress.produced]);
                if progress.status == FramedEncoderStatus::Finished
                    || progress.status == FramedEncoderStatus::NeedsInput
                {
                    assert!(remaining.is_empty());
                    break;
                }
            }
        }
        assert!(resource.is_finished());
    }
    loop {
        let progress = session.process(&mut buffer, FramedEncodeOperation::Finish)?;
        container.extend_from_slice(&buffer[..progress.produced]);
        if progress.status == FramedEncoderStatus::Finished {
            break;
        }
    }
    let mut decoder = FramedDecompressor::new(Default::default())?;
    assert_eq!(decoder.decompress(&container)?.resources[0].data, input);
    Ok(())
}
```

The example marks the last nonempty chunk with `Finish`; for an empty resource,
drive `resource.process(&[], output, Operation::Finish)` to `Finished` too.
Metadata and new resource commands require previous container output to be
drained; otherwise they return `OutputPending` without committing the command.
See [resource lifecycles and metadata](frames.md).

## Ownership and cancellation

Borrowed sessions exclusively borrow their codec owner. Dropping an unfinished
session cancels it; dropping an unfinished framed resource abandons its container.
Forgetting a session requires owner recovery. No drop performs transport I/O.
Owned session variants move the codec into the session when a lifetime-free
holder fits your application better. See [owned sessions](../architecture/owned-sessions.md).
