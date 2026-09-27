# Uninitialized output

Sessions and one-shot slice APIs have `*_uninit` siblings that write into
`&mut [MaybeUninit<u8>]`: spare `Vec` capacity, a foreign buffer, or C memory
that was never initialized. They produce the same bytes, counts, statuses and
errors as the initialized-slice methods, and the crate stays free of `unsafe`
(`src/lib.rs` forbids it outside tests).

## Public API surface

| Initialized | Uninitialized | Owner |
| --- | --- | --- |
| `EncoderSession::process` | `EncoderSession::process_uninit` | `compressor::session` |
| `EncoderSessionOwned::process` | `EncoderSessionOwned::process_uninit` | `compressor::session` |
| `Compressor::compress_to_slice` | `Compressor::compress_to_uninit` | `compressor::encoder` |
| `DecoderSession::process` | `DecoderSession::process_uninit` | `decompressor::session` |
| `DecoderSessionOwned::process` | `DecoderSessionOwned::process_uninit` | `decompressor::session` |
| `Decompressor::decompress_to_slice` | `Decompressor::decompress_to_uninit` | `decompressor::decoder` |

`flush` and `finish` have no uninitialized siblings: they are shorthands for
`process`. Dictionary one-shots and framed sessions have none either.

The contract every method keeps: on success exactly `output[..produced]` (or
`dst[..written]`) is initialized and no byte after it is written. Calls of the
initialized and uninitialized method may be mixed on one session. After a
decoder `DecodeFailure`, its `produced` prefix is initialized as well; after an
encoder error, or a decoder error other than `OutputTooSmall`, callers treat
the destination as uninitialized.

## Why a separate path

Safe Rust can write a `MaybeUninit<u8>` but can neither read one back nor view
a range of them as `&mut [u8]`; `write_copy_of_slice` (the only safe view, and
itself a copy) needs Rust 1.93 and the MSRV is 1.89. Two existing fast paths
read their destination and so cannot run on uninitialized memory:

- the q0/q1 in-place fragment writer (`FastEncoder::encode_block_into`),
  whose bit writer keeps a partial byte, writes 8-byte words read-modify-write,
  rewinds and patches meta-block headers in the caller's slice;
- the decoder's linear one-shot delivery (`Delivery::Linear`), which uses the
  caller's slice as the first member's history.

The uninitialized methods take the paths that already exist for small
destinations instead: encoder scratch followed by one copy, and ring delivery.
The initialized methods are unchanged and keep both fast paths.

## Compressor

```mermaid
classDiagram
    class Destination {
        <<private enum, core::stream>>
        Slice(&mut [u8])
        Uninit(&mut [MaybeUninit u8])
        Append(&mut Vec u8)
    }
    class Output {
        -Destination destination
        -usize produced
        +append(bytes) usize
    }
    class OperationState {
        +process(.., &mut [u8], ..)
        -run(.., Destination, ..)
    }
    Output --> Destination
    OperationState ..> Output : builds per call
```

`SessionCore` and `OwnedSessionCore` forward `process_uninit` to
`OperationState::run` with `Destination::Uninit`; `process` keeps its
`&mut [u8]` entry, which the framed resource driver also calls, and wraps it in
`Destination::Slice`. The one-shot `compress_to_slice_attached` and
`compress_to_uninit_attached` share `driver::compress_to_destination`, which
also writes the empty-input stream through `Output::append`.

```mermaid
flowchart TD
    Block[Delivery::encode block] --> Fast{Fast encoder, not Flush?}
    Fast -->|no| Scratch[encode_block_with into retained scratch]
    Fast -->|yes| Kind{destination}
    Kind -->|Slice with room for fragment_reserve| InPlace[encode_block_into caller slice]
    Kind -->|Append| Vec[encode_block_append into Vec]
    Kind -->|Uninit, or Slice too small| Scratch
    Scratch --> Append[Output::append copies what fits]
    Append --> Rest{bytes left over?}
    Rest -->|session| Pending[keep in pending for the next call]
    Rest -->|one-shot| Small[OutputTooSmall]
```

`Output::append` copies into `Uninit` through `shared::uninit::copy_to_uninit`,
a `zip` + `MaybeUninit::write` loop that compiles to a `memcpy` and keeps the
MSRV. It copies exactly the bytes it counts, which is what makes the
"nothing past `produced`" contract hold; the in-place `Slice` path may leave
scratch bytes past `produced`, which initialized callers never relied on.

## Decompressor

```mermaid
classDiagram
    class Sink {
        <<private enum, core::stream>>
        Init(&mut [u8])
        Uninit(&mut [MaybeUninit u8])
        +len() usize
        +put(index, byte)
        +copy(start, bytes)
        +history() initialized slice or empty
        +take_history() initialized slice or empty
    }
    class Output {
        +Sink bytes
        +bool linear
        +Option collect
        +usize produced
    }
    Output --> Sink
```

Every write of decoded bytes into the destination goes through `Sink::put`
(per-byte literal tails, `emit`) or `Sink::copy` (ring flushes, stored
meta-blocks, prefix runs). The `match` sits in those helpers, outside the bulk
command loop, which works on the ring or on the linear slice it took out with
`take_history`. Only `Sink::Init` can be linear history: `history` and
`take_history` return an empty slice for `Uninit`, and `Uninit` is only ever
built with `Delivery::Slice`, where `linear` is false.

```mermaid
sequenceDiagram
    participant API as DecoderSession / Decompressor
    participant Op as OperationState
    participant Stream as core::Stream
    participant Ring as history ring
    participant Sink as Sink::Uninit
    API->>Op: process_uninit(input, output, operation)
    Op->>Op: run(Sink::Uninit(output), Delivery::Slice)
    Op->>Stream: run(input, Output)
    Stream->>Ring: decode commands into the ring
    Stream->>Sink: flush_ring → copy(produced, ring bytes)
    Stream->>Sink: literal tails → put(produced, byte)
    Stream-->>Op: Stop and produced
    Op-->>API: DecodeProgress or DecodeFailure
```

`decompress_to_uninit` runs one `process_uninit(.., Finish)` on a fresh session
and shares `one_shot_outcome` with `decompress_to_slice`, so `OutputTooSmall`
and `TrailingData` are reported identically.

## C ABI

`mbrotli-ffi` views the caller's output as `&mut [MaybeUninit<u8>]` and calls
`compress_to_uninit` and `decompress_to_uninit`, so an uninitialized C buffer
is never turned into a `&mut [u8]`. Its empty-stream and stored-stream
fallbacks write through `MaybeUninit::write`. See [C ABI](c-abi.md).

## Invariants

- An uninitialized destination is never read, and no byte past the reported
  count is written.
- Uninitialized and initialized methods produce identical streams: the fast
  encoder's in-place and scratch paths are already byte-identical, and ring and
  linear decoder delivery write the same bytes.
- Choosing between `Sink` or `Destination` variants happens once per call or
  per helper invocation, never inside the SIMD copy kernels.

## Verification

- `tests/encode_uninit.rs`: `process_uninit` and mixed calls against `process`
  for every quality, two windows, output windows from 1 byte to 1 MiB (the
  latter drives the q0/q1 in-place path on the initialized side), sentinel
  checks past `produced`, owned sessions, and `compress_to_uninit` against
  `compress_to_slice` including short and empty destinations.
- `tests/decode_uninit.rs`: `process_uninit` against `process` across qualities,
  input chunks and output windows, a corrupt stream's failure progress, owned
  sessions, and `decompress_to_uninit` against `decompress_to_slice` for
  success, `OutputTooSmall`, trailing and truncated input.
- AFL: `encoder_session` and `decoder_session` drive borrowed and owned
  sessions with `process` and `process_uninit` mixed call by call, check that
  nothing is written past `produced`, and restart owned sessions with `reinit`
  from every state; `streaming_equivalence` and `output_capacity` compare
  `compress_to_uninit` with the initialized one-shots, and `decompress`
  compares `decompress_to_uninit` with ring delivery.
- Unit tests in `shared::uninit` and the `mbrotli-ffi` core tests, which now
  run on uninitialized destinations.

## Known gaps

- q0/q1 `process_uninit` and `compress_to_uninit` copy each block once from
  scratch; the initialized methods write it in place when the destination has
  room for a whole fragment.
- `decompress_to_uninit` decodes through the ring and copies out, where
  `decompress_to_slice` uses the destination as history; `mbrotli_decompress`
  inherits that cost.
- No uninitialized variants for dictionary one-shots or framed sessions.
