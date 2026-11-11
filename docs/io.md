# Read / Write I/O

Use std adapters to connect the codecs to files, network streams, in-memory
buffers, and other implementations of `Read` or `Write`. Adapters drive the same
sessions as the [Sans I/O APIs](sans-io-compression.md), adding buffering
and synchronous I/O conventions.

## API map

| Operation | Pull bytes through a reader | Push bytes through a writer |
| --- | --- | --- |
| Raw compression | `Compressor::reader` | `Compressor::writer` |
| Raw decompression | `Decompressor::reader` | `Decompressor::writer` |
| Parallel compression | `ParallelCompressor::reader` + task queue | `ParallelCompressor::writer` + task queue |
| Decompress parallel output | `Decompressor::reader` | `Decompressor::writer` |
| Framed compression · experimental | `FramedCompressor::framed_reader` over complete borrowed resource inputs | `FramedCompressor::framed_writer` with resource writers |
| Framed decompression · experimental | `FramedDecompressor::framed_reader` → events; `framed_seek_reader` → selected resource `Read` | Drive framed decoder events and write payload to your sink |

The library has no dedicated framed decoder `Write` adapter. Its event API keeps
resource boundaries and metadata visible; forward each payload event to an
appropriate `Write` destination. It also has no parallel decoder: parallel
compression produces one ordinary raw Brotli stream.

All adapters on this page require std. Enable `experimental` for framing.
`no_std` removes the std surface even when std is also enabled.

## Raw compression and decompression through `Read`

An encoder reader consumes **plain** bytes and yields **compressed** bytes.
A decoder reader consumes compressed bytes and yields restored bytes.
`std::io::copy` drives each one to EOF. Use a `File` or socket in place of a slice.

```rust
use mbrotli::{Compressor, Decompressor, EncoderConfig, InputSize, Quality};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = b"pull plain bytes through the encoder\n".repeat(100);
    let mut encoder = Compressor::new(
        EncoderConfig::default().with_quality(Quality::Q5),
    )?;
    let stream = InputSize::Exact(input.len() as u64).into();
    let mut reader = encoder.reader(input.as_slice(), stream)?;
    let mut compressed = Vec::new();
    std::io::copy(&mut reader, &mut compressed)?;
    drop(reader);

    let mut decoder = Decompressor::new(Default::default())?;
    let mut reader = decoder.reader(compressed.as_slice(), Default::default())?;
    let mut restored = Vec::new();
    std::io::copy(&mut reader, &mut restored)?;
    assert_eq!(restored, input);
    Ok(())
}
```

When the total input size is unknown, use the default stream configuration for
the encoder. Reading a decoder to EOF is necessary to observe final validation
errors. A raw decoder reader can read past a member boundary; recover its source
and buffered suffix with `into_parts` when another protocol message follows.

## Raw compression and decompression through `Write`

An encoder writer accepts plain bytes; a decoder writer accepts compressed bytes.
Each owns its sink and borrows its codec owner. Finalize **both** writers.

```rust
use mbrotli::{Compressor, Decompressor, EncoderConfig, Quality};
use std::io::Write;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = b"push input into a writer\n".repeat(100);
    let mut encoder = Compressor::new(
        EncoderConfig::default().with_quality(Quality::Q5),
    )?;
    let mut writer = encoder.writer(Vec::new(), Default::default())?;
    for chunk in input.chunks(13) {
        writer.write_all(chunk)?;
    }
    let compressed = writer.finish().map_err(mbrotli::io::FinishError::into_error)?;

    let mut decoder = Decompressor::new(Default::default())?;
    let mut writer = decoder.writer(Vec::new(), Default::default())?;
    for chunk in compressed.chunks(3) {
        writer.write_all(chunk)?;
    }
    let restored = writer.finish().map_err(mbrotli::io::FinishError::into_error)?;
    assert_eq!(restored, input);
    Ok(())
}
```

A decoder writer's `finish` checks that input ends at a valid stream boundary;
`flush` only drains output and flushes the sink. Encoder `flush` also creates an
intermediate decoding boundary and can change compressed size. Dropping a writer
does not finalize or flush it.

## Parallel compression through `Read` and `Write`

Both constructors return an adapter **and a task queue**. Run that queue on
independent workers while using the adapter; reads, writes, and finish can block
waiting for tasks. A queue with no running executor cannot make progress.

This reader example compresses across scoped threads, then uses an ordinary
decoder reader to restore the assembled raw stream:

```rust
use mbrotli::compressor::parallel::{ParallelCompressor, ParallelConfig, TaskCount};
use mbrotli::{Decompressor, EncoderConfig, Quality};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = b"parallel reader with caller-owned workers\n".repeat(220_000);
    let mut encoder = ParallelCompressor::new(
        EncoderConfig::default().with_quality(Quality::Q5),
        ParallelConfig::default(),
    )?;
    let mut compressed = Vec::new();
    std::thread::scope(|scope| -> Result<(), Box<dyn std::error::Error>> {
        let (mut reader, queue) = encoder.reader(input.as_slice(), TaskCount::try_from(4)?)?;
        for _ in 0..4 {
            let worker_queue = queue.clone();
            scope.spawn(move || worker_queue.into_iter().for_each(|task| task.run()));
        }
        drop(queue);
        std::io::copy(&mut reader, &mut compressed)?;
        Ok(())
    })?;

    let mut decoder = Decompressor::new(Default::default())?;
    let mut reader = decoder.reader(compressed.as_slice(), Default::default())?;
    let mut restored = Vec::new();
    std::io::copy(&mut reader, &mut restored)?;
    assert_eq!(restored, input);
    Ok(())
}
```

For the writer direction, the [complete parallel writer recipe](parallel.md#reader-and-writer-adapters)
copies a source into the returned writer, then finishes it while workers keep
running. The task window bounds outstanding segments; the parallel writer's
`flush` ends the current segment early. Decode its output with either raw adapter
shown above. See [parallel output and backpressure](../architecture/parallel-stream.md).

## Framed compression through readers and resource writers

`framed_reader` encodes a complete borrowed `FramedInput` into a `Read` stream.
It does not accept resources that arrive later. Use `framed_writer` when input
arrives gradually: start a resource, write its payload, finish it, release its
borrow, then start another resource. Finish the enclosing container last.

The [framed writer recipe](frames.md#write-resources-and-metadata) demonstrates
compressed and uncompressed resource writers and metadata. Here is the reader
direction, paired with sequential event decoding:

```rust
use mbrotli::framing::{
    FramedCompressor, FramedDecompressor, FramedEvent,
    FramedInput, FramedItem, FramedResource,
};
use std::io::BufReader;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = b"a resource exposed as an encoded reader";
    let items = [FramedItem::Resource(FramedResource::from(input.as_slice()))];
    let mut encoder = FramedCompressor::new(Default::default())?;
    let mut encoded = encoder.framed_reader(
        FramedInput::from(items.as_slice()), Default::default(),
    )?;
    let mut container = Vec::new();
    std::io::copy(&mut encoded, &mut container)?;
    drop(encoded);

    let mut decoder = FramedDecompressor::new(Default::default())?;
    let source = BufReader::new(container.as_slice());
    let mut reader = decoder.framed_reader(source, Default::default())?;
    let mut restored = Vec::new();
    let mut resources = 0;
    while let Some(event) = reader.next_event()? {
        match event {
            FramedEvent::ResourceStart(_) => resources += 1,
            FramedEvent::ResourceData(data) => restored.extend_from_slice(data.bytes),
            _ => {}
        }
    }
    assert!(reader.is_finished());
    assert_eq!(resources, 1);
    assert_eq!(restored, input);
    Ok(())
}
```

## Framed decompression into a `Write` sink

`FramedReader` lends events over a `BufRead` source. Wrap an ordinary `Read`
in `BufReader`. For each `ResourceData` event, send `data.bytes` to your sink with
`write_all`; use `ResourceStart` to select the destination for that resource.
Continue until `next_event` returns `None`, after complete validation.

```rust
use mbrotli::framing::{
    FramedCompressor, FramedDecompressor, FramedEvent,
    FramedInput, FramedItem, FramedResource,
};
use std::io::{BufReader, Write};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let items = [
        FramedItem::Resource(FramedResource::from(b"first".as_slice())),
        FramedItem::Resource(FramedResource::from(b"second".as_slice())),
    ];
    let mut encoder = FramedCompressor::new(Default::default())?;
    let container = encoder.compress(FramedInput::from(items.as_slice()))?;
    let mut decoder = FramedDecompressor::new(Default::default())?;
    let mut reader = decoder.framed_reader(
        BufReader::new(container.as_slice()), Default::default(),
    )?;
    let mut sinks: Vec<Vec<u8>> = Vec::new();
    while let Some(event) = reader.next_event()? {
        match event {
            FramedEvent::ResourceStart(_) => sinks.push(Vec::new()),
            FramedEvent::ResourceData(data) => {
                let sink = sinks.last_mut().ok_or("payload without a resource")?;
                sink.write_all(data.bytes)?;
            }
            _ => {}
        }
    }
    assert!(reader.is_finished());
    assert_eq!(sinks, vec![b"first".to_vec(), b"second".to_vec()]);
    Ok(())
}
```

This recipe uses in-memory sinks; a resource router can instead choose files or
other writers. If a sink fails after an event was read, retain its unwritten
suffix before advancing to the next event. `FramedReader::partial_output` exposes
payload produced on a failing reader call. Keep protocol bytes after the
container by recovering the buffered source with `into_inner`.

For `Read + Seek`, use [indexed resource reads](frames.md#indexed-resource-reads):
`framed_seek_reader` opens the directory and `resource(index)` returns a
`ResourceReader` implementing `Read`, suitable for `std::io::copy`.
For push-driven compressed input, use the [native framed decoder](sans-io-decompression.md#decode-a-framing-container-as-events)
and route the same resource events to sinks.

## Completion, retries, and ownership

| Adapter | Complete operation | Recover after a failure |
| --- | --- | --- |
| Raw encoder / decoder reader | Read to EOF | Decoder `into_parts` preserves read-ahead; codec errors are terminal |
| Raw encoder / decoder writer | `finish` or retryable `try_finish` | `FinishError::into_parts` returns error and writer |
| Parallel reader | Read to EOF with active workers | `into_parts` preserves read-ahead; keep queue execution alive |
| Parallel writer | `finish` with active workers | `FinishError::into_parts` returns error and adapter |
| Framed encoded reader | Read to EOF | Dropping early abandons that container operation |
| Framed writer | Each resource `try_finish`, then container `finish` | `FramingFinishError` exposes `writer` and `error` |
| Framed event reader | `next_event` until `None` | Inspect `partial_output`; `into_inner` preserves buffered source suffix |

Short sink writes and errors must not cause accepted input to be replayed.
The writer adapters retain pending output, and a later call may report an error
after an earlier call already accepted input. `WouldBlock` is not EOF. If you
need explicit readiness handling, use native sessions and drive them when your
runtime says buffers are ready. See [streaming completion](streaming.md)
and [framed retry mechanics](../architecture/framing.md#state-cancellation-and-retry).
