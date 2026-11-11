# Framing containers

Package multiple resources, metadata, and optional dictionary references in an
experimental Shared Brotli container. This is useful when an application needs
resource boundaries or indexed access in addition to compression.

## Enable framing

```toml
[dependencies]
mbrotli = { version = "0.5.20", features = ["experimental"] }
```

The examples use std, compression, and decompression. Experimental APIs may
change in a patch release. A framed container needs `FramedDecompressor`;
the raw `Decompressor` API accepts raw Brotli members.

| Concept | Meaning |
| --- | --- |
| Container | The enclosing structure, with resources and optional metadata/directory/footer |
| Resource | One logical payload, compressed or stored verbatim |
| Chunk | A bounded portion of a resource on the wire; several chunks can share decoder state |
| Directory | Index for the full profile, used for seeking to selected resources |

The library's parallel compressor emits **one raw Brotli stream**. It does not
emit framing containers. See [parallel compression](parallel.md) when the goal
is compressing one input across cores.

## One container, two resources

Use borrowed inputs when all resource bytes are available. The first resource
below is Brotli-compressed; the second is explicitly stored without compression.

```rust
use mbrotli::framing::{
    FramedCompressor, FramedDecompressor, FramedEncodeConfig, FramedInput,
    FramedItem, FramedResource, ResourceEncoding,
};
use mbrotli::{EncoderConfig, Quality};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let text = b"a document with repeated content\n".repeat(1000);
    let binary = [0x91, 0x02, 0x7f, 0x00];
    let mut stored = FramedResource::from(binary.as_slice());
    stored.encoding = ResourceEncoding::Uncompressed;
    let items = [
        FramedItem::Resource(FramedResource::from(text.as_slice())),
        FramedItem::Resource(stored),
    ];

    let config = FramedEncodeConfig::default().with_encoder_config(
        EncoderConfig::default().with_quality(Quality::Q5),
    );
    let mut encoder = FramedCompressor::new(config)?;
    let container = encoder.compress(FramedInput::from(items.as_slice()))?;

    let mut decoder = FramedDecompressor::new(Default::default())?;
    let decoded = decoder.decompress(&container)?;
    assert_eq!(decoded.resources.len(), 2);
    assert_eq!(decoded.resources[0].data, text);
    assert_eq!(decoded.resources[1].data, binary);
    Ok(())
}
```

`compress_into` appends a container to a reusable Vec; `compress_to_slice`
writes into caller storage. The owner can be reused for later containers.
The [framed compressor specification](../architecture/framing.md) describes
size contracts, retention, and native incremental output APIs.

## Write resources and metadata

Use a writer when resource input arrives gradually. Resource metadata precedes
the resource it describes. Finish each resource before starting the next one,
then finish the container.

```rust
use mbrotli::framing::{
    FramedCompressor, FramedDecompressor, FramedEncodeConfig,
    FramingConfig, MetadataField, MetadataKind,
};
use mbrotli::{EncoderConfig, Quality};
use std::io::Write;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = FramedEncodeConfig::default()
        .with_encoder_config(EncoderConfig::default().with_quality(Quality::Q5))
        .with_framing_config(FramingConfig {
            chunk_bytes: 4096,
            ..Default::default()
        });
    let mut encoder = FramedCompressor::new(config)?;
    let mut writer = encoder.framed_writer(Vec::new(), Default::default())?;
    writer.metadata(MetadataKind::Resource, &[
        MetadataField { code: *b"id", value: b"notes.txt" },
    ])?;
    {
        let mut resource = writer.resource(Default::default(), Default::default())?;
        resource.write_all(b"first part\n")?;
        resource.write_all(b"second part\n")?;
        resource.try_finish()?;
    }
    {
        let mut resource = writer.uncompressed_resource(Default::default())?;
        resource.write_all(&[1, 2, 3, 4])?;
        resource.try_finish()?;
    }
    let container = writer.finish().map_err(|failure| failure.error)?;

    let mut decoder = FramedDecompressor::new(Default::default())?;
    let decoded = decoder.decompress(&container)?;
    assert_eq!(decoded.resources[0].data, b"first part\nsecond part\n");
    assert_eq!(decoded.resources[0].metadata.as_ref().and_then(|m| m.name()),
               Some("notes.txt"));
    assert_eq!(decoded.resources[1].data, [1, 2, 3, 4]);
    Ok(())
}
```

Neither resource drop nor container drop performs I/O. Dropping an unfinished
resource abandons its container. `try_finish` supports retrying resource
finalization; a failed consuming container `finish` retains the writer in
`FramingFinishError` for recovery through its `writer` and `error` fields. The
in-memory example above keeps the error and discards the writer. See the
[retry state machine](../architecture/framing.md#state-cancellation-and-retry).

Metadata `id` is a caller-provided UTF-8 name, not an extraction path or a
unique lookup key. Checksums are supplied by the caller; the writer does not
compute them and the decoder does not verify them.

## Indexed resource reads

For a full-profile container on a `Read + Seek` source, open the footer and
directory, then read a selected resource. You can use a `File` in place of the
in-memory `Cursor` below.

```rust
use mbrotli::framing::{
    FramedCompressor, FramedDecompressor, FramedInput,
    FramedItem, FramedResource, ResourceIndex,
};
use std::io::{Cursor, Read};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let items = [
        FramedItem::Resource(FramedResource::from(b"first".as_slice())),
        FramedItem::Resource(FramedResource::from(b"second".as_slice())),
    ];
    let mut encoder = FramedCompressor::new(Default::default())?;
    let container = encoder.compress(FramedInput::from(items.as_slice()))?;

    let mut decoder = FramedDecompressor::new(Default::default())?;
    let mut reader = decoder.framed_seek_reader(Cursor::new(container))?;
    assert_eq!(reader.resources().len(), 2);
    let mut selected = Vec::new();
    reader.resource(ResourceIndex(1))?.read_to_end(&mut selected)?;
    assert_eq!(selected, b"second");
    Ok(())
}
```

Resources are identified by zero-based `ResourceIndex`, independent of metadata
names. A resource that references earlier dictionary content can require
decoding its dependencies. A selected resource reader implements `Read`;
the enclosing reader uses `Seek` to locate container content.
See [indexed decoder mechanics](../architecture/framed-seek-reader.md).

## Limits and streaming decoding

`FramingConfig` bounds encoder chunks, metadata, resource/chunk counts, and
framing storage. `FramedDecodeConfig` / `FramedDecodeLimits` control decoder
budgets; raw `DecoderConfig` limits apply within compressed resources.
Choose limits for the workload before decoding untrusted containers.

For arriving input, `FramedDecompressor::start` exposes incremental events;
`framed_reader` adapts a `BufRead` source. `InputMode::Auto` also accepts raw
Brotli; the default is `FramedOnly`. External dictionaries need a caller-supplied
resolver. See [decoder APIs, limits, and events](../architecture/framed-decoder.md)
and [dictionaries](dictionaries.md#framing-containers).
