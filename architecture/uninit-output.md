# Uninitialized output

Sessions and one-shot slice APIs have `*_uninit` siblings that write into
`&mut [MaybeUninit<u8>]`: spare `Vec` capacity, a foreign buffer, or C memory
that was never initialized. They produce the same bytes, counts, statuses and
errors as the initialized-slice methods, and the crate stays free of `unsafe`
(`src/lib.rs` forbids it outside tests). The one place that has to read back
what it wrote into such memory, the decoder's one-shot history, does it
through the `borrowed-buf` crate's `BorrowedBuf`, whose filled prefix is safe
to view as `&mut [u8]`.

## Public API surface

| Initialized | Uninitialized | Owner |
| --- | --- | --- |
| `EncoderSession::process` | `EncoderSession::process_uninit` | `compressor::session` |
| `EncoderSessionOwned::process` | `EncoderSessionOwned::process_uninit` | `compressor::session` |
| `ParallelEncoderSession::process` | `ParallelEncoderSession::process_uninit` | `compressor::parallel::session` |
| `ParallelEncoderSessionOwned::process` | `ParallelEncoderSessionOwned::process_uninit` | `compressor::parallel::session` |
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
itself a copy) needs Rust 1.93 and the MSRV is 1.89. `BorrowedBuf` (a stable
port of `core::io::BorrowedBuf`) tracks how much of such a slice was written
and views exactly that prefix as `&mut [u8]`; its `unsafe` stays inside that
crate. Two fast paths read their destination:

- the q0/q1 in-place fragment writer (`FastEncoder::encode_block_into`),
  whose bit writer keeps a partial byte, writes 8-byte words read-modify-write,
  rewinds and patches meta-block headers in the caller's slice;
- the decoder's linear one-shot delivery (`Delivery::Linear`), which uses the
  caller's slice as the first member's history.

The encoder's uninitialized methods encode into initialized owned storage and
copy completed bytes to the caller. Fast non-flush sessions use the compressor's
pending backing directly, retaining its initialized length and tracking the
completed prefix separately. One-shot calls and other encoder paths use encoder
scratch. Decoder streaming `process_uninit` delivers through the ring, since a
later call's destination cannot hold the paused member's history. The one-shot
`decompress_to_uninit` keeps linear delivery: it zeroes the destination one
meta-block ahead of the decoder (see [Linear one-shot
history](#linear-one-shot-history)).

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
    Fast -->|no| Greedy{Greedy, Append, not Flush?}
    Greedy -->|no| Scratch[encode_block_with into retained scratch]
    Greedy -->|yes| GreedyAppend[encode_block_append]
    GreedyAppend --> Raw{Known verbatim block?}
    Raw -->|yes| DirectRaw[Write ring payload directly to initialized Vec]
    Raw -->|no| GreedyScratch[Compress into scratch, then append]
    Fast -->|yes| Kind{destination}
    Kind -->|Slice with room for fragment_reserve| InPlace[encode_block_into caller slice]
    Kind -->|Append| Vec[encode_block_append into Vec]
    Kind -->|Uninit, or Slice too small| Resumable{session permits pending?}
    Resumable -->|no| Scratch
    Resumable -->|yes| Backing[Fixed writer in initialized pending backing]
    Backing --> Publish[Publish completed end after success]
    Publish --> Drain[Copy pending from served to completed end]
    Drain --> Retain[Retain initialized length; reset cursors after complete delivery]
    Scratch --> Append[Output::append copies what fits]
    Append --> Rest{bytes left over?}
    Rest -->|session| Pending[keep in pending for the next call]
    Rest -->|one-shot| Small[OutputTooSmall]
```

The greedy direct-append branch accepts only `Destination::Append`, whose Vec
contains an initialized prefix that the bit writer may read. It writes known
verbatim payloads directly and leaves compressed trials scratch-backed.
`Destination::Uninit` never enters this branch: its initialized scratch is still
copied through `Output::append`, preserving exactly the same produced-prefix
contract and leaving bytes beyond it untouched.

`Output::append` copies into `Uninit` through `shared::uninit::copy_to_uninit`,
a `zip` + `MaybeUninit::write` loop that compiles to a `memcpy` and keeps the
MSRV. It copies exactly the bytes it counts, which is what makes the
"nothing past `produced`" contract hold; the in-place `Slice` path may leave
scratch bytes past `produced`, which initialized callers never relied on.

## Parallel streaming sessions

A parallel session never encodes into the caller's slice: workers stage each
segment in a `Vec<u8>`, and the session only copies finished parts out in
input order. Its delivery therefore never reads the destination, and both
methods share one path. `core::stream::Stream::process` and its `drain` are
generic over a private `Sink` trait (`len`, `put(at, bytes)`), implemented for
`[u8]` (`copy_from_slice`) and `[MaybeUninit<u8>]` (`copy_to_uninit`). Each
public method instantiates it once, so the initialized path compiles to the
same slice copies as before and no call chooses a variant at run time.

```mermaid
sequenceDiagram
    participant API as ParallelEncoderSession{,Owned}
    participant Stream as core::Stream
    participant Flight as finished parts
    participant Sink as Sink impl
    API->>Stream: process::<[MaybeUninit u8]>(parent, input, output, operation)
    Stream->>Flight: collect published completions
    Stream->>Sink: drain(output, 0): put(produced, part bytes)
    Stream->>Stream: accept input, queue full segments
    Stream->>Sink: drain(output, produced)
    Stream-->>API: ParallelProgress
```

`drain` writes exactly the `take` bytes it adds to `produced`, which is what
keeps "nothing past `produced`". See [Parallel streaming
sessions](parallel-stream.md).

## Decompressor

```mermaid
classDiagram
    class Sink~'a~ {
        <<private trait, core::stream>>
        +LINEAR bool
        +len() usize
        +put(index, byte)
        +copy(start, bytes)
        +history() initialized slice or empty
        +take_history() initialized slice or empty
        +restore_history(slice)
    }
    class InitSlice["&'a mut [u8]"]
    class UninitSlice["&'a mut [MaybeUninit u8]"]
    class Output~O: Sink~ {
        +O bytes
        +bool linear
        +Option collect
        +usize produced
    }
    Sink <|.. InitSlice
    Sink <|.. UninitSlice
    Output --> Sink
```

Every write of decoded bytes into the destination goes through `Sink::put`
(per-byte literal tails, `emit`) or `Sink::copy` (ring flushes, stored
meta-blocks, prefix runs). The bulk command loop works on the ring or on the
linear slice it took out with `take_history` and hands back with
`restore_history`. Only the initialized slice can be linear history:
`history` and `take_history` return an empty slice for the uninitialized one,
`restore_history` accepts only that empty slice back, and an uninitialized
sink is only ever run with `Delivery::Slice` (by `process_uninit`), where
`linear` is false. Its
`Sink::LINEAR` constant is false as well, so `Stream::run` never selects the
linear state machine for it and that instantiation is never generated (see
[Owned decoder output](decoder-owned-output.md#linear-slice-history)).

`OperationState::run`, `Stream::run`, `run_stages`, `fast`, `emit`,
`flush_ring`, `copy_ring` and `write_ring` are generic over the sink, so each
destination type gets its own instantiation and no call chooses a variant at
run time. Below `Stream::run` they are also generic over `const LINEAR: bool`,
giving three instantiations: initialized linear, initialized ring and
uninitialized ring. The first version matched on a `Sink` enum inside those helpers;
the match itself was cheap, but `run_stages` inlines every stage and the
SIMD command loop into one function, and the extra arms changed that
function's register allocation. Decoding alice29 then executed 9% more
instructions (callgrind, q0 and q5) and the cold decoder comparison was 4-7%
slower on text and binary corpora. The initialized instantiation now compiles
to the same slice writes as before uninitialized output existed.

```mermaid
sequenceDiagram
    participant API as DecoderSession / Decompressor
    participant Op as OperationState
    participant Stream as core::Stream
    participant Ring as history ring
    participant Sink as uninitialized Sink
    API->>Op: process_uninit(input, output, operation)
    Op->>Op: run::<&mut [MaybeUninit u8]>(output, Delivery::Slice)
    Op->>Stream: run(input, Output)
    Stream->>Ring: decode commands into the ring
    Stream->>Sink: flush_ring → copy(produced, ring bytes)
    Stream->>Sink: literal tails → put(produced, byte)
    Stream-->>Op: Stop and produced
    Op-->>API: DecodeProgress or DecodeFailure
```

`decompress_to_uninit` first asks `stored_one_shot`, the check
`Decompressor::decompress` also uses, whether `src` is one complete stored
member under a configuration without limits or other members; if its payload
fits in `dst`, it is copied with `copy_to_uninit` and no session or ring is
created. Otherwise, including a stored payload that does not fit, it runs
`DecoderSession::finish_linear_uninit` on a fresh session and shares
`one_shot_outcome` with `decompress_to_slice`, so `OutputTooSmall` and
`TrailingData` are reported identically.

### Linear one-shot history

`finish_linear_uninit` wraps `dst` in a `BorrowedBuf<u8>` whose filled prefix
is the decoder's linear history: the bytes decoded so far plus zeros the
decoder is about to overwrite. Each round passes `filled_mut()` to
`OperationState::process` with `Delivery::Linear`, which resumes at
`total_out` with the earlier output in front of it as history (the first call
starts at an empty prefix). The initialized-slice instantiation of the decode
loop runs; no uninitialized one is involved.

```mermaid
sequenceDiagram
    participant API as decompress_to_uninit
    participant S as finish_linear_uninit
    participant B as BorrowedBuf over dst
    participant Op as OperationState::process (Linear)
    API->>S: src, dst
    S->>B: from(dst): empty filled prefix
    loop until Finished, an error, or dst is full
        S->>Op: input rest, filled_mut(), Finish
        Op-->>S: progress (NeedsOutput when the prefix is used up)
        S->>S: grow = clamp(produced + declared_remaining - filled, 1, 32 KiB)
        S->>B: zero_extend(grow): cursor.append_fill(grow, 0)
    end
    S-->>API: summed consumed, produced, last status
```

```mermaid
stateDiagram-v2
    [*] --> Decode: filled = 0
    Decode --> Grow: NeedsOutput and room left
    Grow --> Decode: filled += min(meta-block rest, 32 KiB, room)
    Decode --> Done: Finished or NeedsInput
    Decode --> TooSmall: NeedsOutput and dst full
    Decode --> Failed: decode error
    Done --> [*]
    TooSmall --> [*]: OutputTooSmall, dst fully decoded
    Failed --> [*]
```

The first call parses the window and meta-block headers and stops at the
first byte to write; from then on `declared_remaining` is the current
meta-block's undecoded length. Growing by at most that keeps the zeroed prefix
inside bytes the stream will produce, so on success nothing past `written` is
written, as for every uninitialized method. The decode loop already bounds its
speculative 16- and 32-byte copies by the meta-block end and the slice end.
A pause outside a meta-block's payload grows by one byte, which guarantees
progress. After the first member ends, later members (with
`MemberMode::Concatenated`) are delivered from the ring into the same growing
prefix at their offset.

`zero_extend` is one `BorrowedCursor::append_fill(len, 0)` (borrowed-buf
0.1.1), a memset; copying the zeros from a 4 KiB static block, the only way
before that method existed, took 3-7% longer on highly compressible data.
The 32 KiB cap (`ZERO_AHEAD_STEP`, shared with the `Vec` path of
`decompress_into`) keeps the freshly zeroed lines in L1 when the decoder
overwrites them: on exact-sized destinations (i7-13700KF, one core) caps of
16, 32 and 64 KiB took 1.023, 1.019 and 1.074 times as long as
`decompress_to_slice`. The ring path took 1.17 times, so the one-shot takes
12% less time than before in geometric mean: 15-20% on 1 MiB of text, 3-9%
on literary texts, 6-13% on binary and 28-41% on data compressed beyond
100:1; stored members and 1 KiB outputs are unchanged.

## C ABI

`mbrotli-ffi` views the caller's output as `&mut [MaybeUninit<u8>]` and calls
`compress_to_uninit` and `decompress_to_uninit`. Only a decoding destination
of at most 1 KiB is zeroed in full (`BorrowedBuf::ensure_init`) and decoded
with `decompress_to_slice`, which saves the extra decoding call per
meta-block. An uninitialized C buffer is never viewed as `&mut [u8]` before it
has been zeroed. See [C ABI](c-abi.md).

## Invariants

- An uninitialized destination is never read before it is written, and the
  uninitialized methods write no byte past the reported count. The decoder's
  linear one-shot reads back only `BorrowedBuf`'s filled prefix, which it
  wrote itself (decoded bytes or zeros). The C ABI may zero a whole
  destination first, as its header documents.
- Uninitialized and initialized methods produce identical streams: the fast
  encoder's in-place and scratch paths are already byte-identical, and ring and
  linear decoder delivery write the same bytes.
- The encoder chooses between `Destination` variants once per call or per
  helper invocation, never inside the SIMD copy kernels. The parallel session
  is monomorphized per `Sink` type, as the decoder is. The decoder does not
  choose at run time at all: it is monomorphized per `Sink` type, so the
  initialized decode loop carries no uninitialized-output code.

## Verification

- `tests/encode_uninit.rs`: `process_uninit` and mixed calls against `process`
  for every quality, two windows, output windows from 1 byte to 1 MiB (the
  latter drives the q0/q1 in-place path on the initialized side), sentinel
  checks past `produced`, owned sessions, and `compress_to_uninit` against
  `compress_to_slice` including short and empty destinations.
- `tests/decode_uninit.rs`: `process_uninit` against `process` across qualities,
  input chunks and output windows, a corrupt stream's failure progress, owned
  sessions, and `decompress_to_uninit` against `decompress_to_slice` for
  success, `OutputTooSmall`, trailing and truncated input; outputs many
  zeroing steps long, `OutputTooSmall` at every step boundary, concatenated
  members, output limits and corrupt input, each against
  `decompress_to_slice` with sentinels past the result.
- `tests/parallel_stream.rs`: `process_uninit` and mixed calls against the
  batch for four qualities, windows 1-4, inline and threaded executors and
  output buffers down to one byte, the serial fallback and segment edges, an
  empty destination and a finished stream (sentinels untouched), a failed
  stream, and owned sessions.
- AFL: `encoder_session` and `decoder_session` drive borrowed and owned
  sessions with `process` and `process_uninit` mixed call by call, check that
  nothing is written past `produced`, and restart owned sessions with `reinit`
  from every state; `streaming_equivalence` and `output_capacity` compare
  `compress_to_uninit` with the initialized one-shots, and `decompress`
  compares `decompress_to_uninit` with ring delivery; `parallel` alternates
  `process` and `process_uninit` on its streamed session under the same
  sentinel check and batch-identity oracle.
- Unit tests in `shared::uninit` (including `zero_extend`), resumable
  `Delivery::Linear` in `decompressor::core::session`, and the `mbrotli-ffi`
  core tests, which run on uninitialized destinations.

## Known gaps

- q0/q1 `process_uninit` and `compress_to_uninit` copy each block once from
  scratch; the initialized methods write it in place when the destination has
  room for a whole fragment.
- `decompress_to_uninit` writes every output byte twice, zero first: 1.2%
  slower than `decompress_to_slice` into an initialized slice in geometric
  mean, most on data compressed beyond 100:1 and on 1 MiB of repetitive text.
  Safe code cannot view memory as `&mut [u8]` before writing it; avoiding the
  zeroing would need a decode loop that writes only through the cursor.
- Each meta-block (each 32 KiB within one) costs `decompress_to_uninit` one
  more `OperationState::process` call. On 1 KiB outputs this leaves it about
  7% behind zeroing the whole destination; the C ABI does that below 1 KiB.
- `process_uninit` still delivers through the ring.
- No uninitialized variants for dictionary one-shots or framed sessions.
- A program that calls `process_uninit` links a second instantiation of the
  decode loop: about 106 KiB more `.text` on x86_64. `decompress_to_uninit`
  runs the initialized instantiation and does not pay it.
- In a program that links both `decompress_to_slice` and
  `decompress_to_uninit`, `OperationState::process` has two one-shot callers
  and is no longer inlined into `decompress_to_slice`: about 90-116 more
  instructions per call (6 ns, measurable only on outputs of a few KiB).

### C session destinations

`mbrotli-ffi` encoder/decoder `process`, `flush` and `finish` all delegate to
owned-session `process_uninit`. They never create an initialized slice over C
output. See [C ABI sessions](c-abi.md#streaming-sessions) for count, error and
pointer contracts.

```mermaid
graph LR
    C[C process / flush / finish] --> V[core::sessions: validate regions]
    V --> U[MaybeUninit output slice]
    U --> O[owned session process_uninit]
    O --> P[initialized prefix and exact progress]
```
