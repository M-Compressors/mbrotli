# Owned decoder output

The owned Vec path can recognize stored members directly or transfer its history
allocation to the caller. The one-shot slice path decodes its first member with
the caller's slice as history. The same decoder state machine enforces decoded bytes,
trailing-data policy, window limits, dictionaries and resource budgets.

## Ownership, control and data flow

Private `core::stored` first recognizes the exact three-byte header consisting
of a four-bit standard window, a non-final raw block and a 16-bit length. It
checks the declared window, exact payload length and final byte `0x03`. Other
shapes use the existing demand-driven window/meta-block parsers to recognize
an empty member or one raw block followed by a final empty block.
It verifies window policy, all padding, exact payload bounds and the absence of
a tail, then returns a borrowed slice. Unsupported or malformed shapes return
`None` and enter the normal driver, which owns public error reporting.
`decompress` uses this path only for single-member operations without numeric
limits and without an abandoned session. It reserves fallibly, copies once,
and applies retention policy. No full state machine or history is necessary.

Otherwise the Vec driver probes with empty output. A zero-capacity destination,
fresh workspace, single-member mode and absent dictionary permit collection.
The private session passes `Output::collect = Some(window_size)` to the same
state machine. Ready/fast-end still enforce output policies. Emit and flush
advance progress but do not copy ring bytes to an external slice. Collection
stops before history wraps. Successful complete input transfers the ring's
allocation, truncates its logical length to produced bytes and subtracts its
capacity from live workspace accounting. If the member is larger than its
window, the collected prefix is copied once into the destination, history is
retained and ordinary streaming delivery resumes. Appends, preallocated Vecs,
retained workspaces, dictionaries and concatenation use ordinary delivery.

```mermaid
flowchart TD
    Owned[Owned decode] --> Stored{eligible complete stored member?}
    Stored -->|yes| Borrow[borrow validated payload]
    Borrow --> Copy[fallible allocation and one copy]
    Stored -->|no| Probe[probe existing session with empty output]
    Probe --> Eligible{fresh single member and empty allocation?}
    Eligible -->|yes| Collect[decode into history; retain progress and limits]
    Eligible -->|no| Stream[ordinary slice delivery]
    Collect --> Complete{finished before wrap?}
    Complete -->|yes| Tail[validate exact input end]
    Tail --> Transfer[move allocation to caller; subtract workspace bytes]
    Complete -->|no| Prefix[copy prefix; preserve history]
    Prefix --> Stream
```

Before the first wrap, raw growth reserves a power-of-two allocation, copies
into existing initialized slots and appends the remaining raw bytes, then
zeroes only unused padding. A growing unit-distance copy in the resumable copy
stage fills newly allocated slots with their final byte. Both reserve under
workspace accounting before modifying history/position. Wrapped and other
copies retain the existing baseline/SIMD kernels. All slices remain initialized, all output bytes are actually materialized and
SIMD dispatch stays outside the command and copy loops.

```mermaid
flowchart LR
    Grow[history must grow] --> Reserve[check peak workspace; fallible reserve]
    Reserve --> Raw[raw: append source bytes then initialize padding]
    Reserve --> Repeat[unit distance: resize with repeated byte]
    Reserve --> Other[other paths: ordinary zeroed growth]
    Raw --> History[initialized power-of-two history]
    Repeat --> History
    Other --> History
```

## Linear slice history

`decompress_to_slice` and `decompress_with_dictionary_to_slice` end their
session with one call, so no later call needs the history of a paused member.
They call the private `finish_linear`, which passes `Delivery::Linear` to the
operation. The operation turns it into `Output::linear` only for a call that
starts the operation (`total_in == 0 && total_out == 0`), so the first member
begins at `dst[0]` and every history position equals its slice index. The
member boundary clears the flag; later members in concatenated mode use the
ring as before.

`Output::linear` is read once per call, by `Stream::run`, and nowhere below it.
`run` picks one of two instantiations of the state machine:
`run_stages::<O, true>` when the sink can be history (`Sink::LINEAR`, true
only for `&mut [u8]`) and the flag is set, `run_stages::<O, false>` otherwise.
The `const LINEAR: bool` parameter reaches `fast`, `emit`, `history`,
`flush_ring`, `copy_ring` and `write_ring`, so every "linear or ring?" test is
a compile-time constant. An uninitialized sink never instantiates the linear
machine: its `Sink::LINEAR` is false, so the linear arm is unreachable for it
and is not generated.

The linear command loop therefore carries none of the ring machinery. Ring
growth (`reach!`, `grow_ring`), the unit-distance growth fill
(`repeat_grow`), the wrapping `copy_ring` fallback, the growth limit and the
ring allocation are all absent, and `mask` is the constant `u64::MAX`, so a
position is used directly as a slice index. The command loop is
register-bound, and the dead ring code had shared its registers. Removing it
cut decoded instructions for `decompress_to_slice` by 6.6% on average and
by up to 12.8% on text (see [Known gaps](#known-gaps) for the one corpus
where time did not follow).

With `linear` set the caller's slice is the member's history. The ring is
neither written nor grown. `emit`, raw copies and the byte-exact literal run
write only the slice. Context bytes, prefix-crossing history and every copy read
it. Delivery (`flush_ring`) advances `produced` without copying, as in
collection, so the linear command loop skips the ring-end test after each
literal run and copy and delivers once, when it leaves. The command loop and the resumable copy and prefix stages take the
slice out of `Output` (`core::mem::take`) for their bulk work and put it back
on every exit. The loop's `leave!` does this on pauses and errors.

Bulk work sees the slice only up to `history_end`: the smaller of the call's
fast end and `position + remaining` of the current meta-block. The 16- and
32-byte copy kernels may write up to fifteen bytes past a copy, and the bound
keeps those bytes inside output this meta-block writes. On success or
`OutputTooSmall` the slice matches ring delivery byte for byte, including an
untouched suffix. After other errors, bytes past the delivered prefix may hold
partial output of the failing meta-block. The method has always documented
that written bytes are not rolled back.

`history_mask` indexes both buffers: a power-of-two length gives `len - 1`
(the ring wraps; a power-of-two slice is never indexed at or past its length,
so the mask is the identity), any other length gives `u64::MAX`. The copy
kernels and `previous_bytes` share it, so the SIMD and baseline copies are the
same code in both modes. The linear command loop skips it and uses `u64::MAX`,
the identity on every position it holds.

A copy in the linear command loop always fits unsplit. `space` bounds it by
`out_end - position` (`produced` equals `position` for a linear member), and
`remaining` bounds it by the meta-block, so `position + copy <= history_end`,
which is the slice length the loop sees. If this invariant ever broke, the
branch that the ring machine spends on `copy_ring` returns
`DecodeError::InternalInvariant` instead of panicking.

```mermaid
sequenceDiagram
    participant API as decompress_to_slice
    participant Op as OperationState
    participant Stream as Stream::run
    participant Fast as fast / Copy / Prefix
    API->>Op: finish_linear(src, dst)
    Op->>Op: linear = fresh operation
    Op->>Stream: Output { bytes: dst, linear }
    Stream->>Stream: O::LINEAR && linear → run_stages::<O, true>
    Stream->>Fast: take dst, bound to history_end
    Fast->>Fast: decode and copy inside dst
    Fast-->>Stream: restore dst; produced += delivered
    Stream-->>Op: Stop::Member
    Op->>Op: linear = false for later members
    Op-->>API: progress
```

```mermaid
flowchart TD
    Call[Stream::run] --> Pick{Sink::LINEAR and Output.linear?}
    Pick -->|yes| LinearMachine[run_stages::&lt;O, true&gt;]
    Pick -->|no| RingMachine[run_stages::&lt;O, false&gt;]
    LinearMachine --> Slice[write dst at position; no ring code compiled]
    RingMachine --> Ring[ensure ring; write position & mask]
    Ring --> Deliver{delivers?}
    Deliver -->|slice delivery| CopyOut[flush copies ring bytes to dst]
    Deliver -->|collect| Count[flush advances produced]
    Slice --> Count
```

## Read-ahead accounting

At output pauses and member boundaries, `Bits::unread` returns speculative whole
bytes accepted by the current call so the caller can reoffer the exact suffix.
At input pauses, incomplete fields retain accepted bits. Bytes accepted by an
earlier call are never subtracted from the current call's consumed count.

```mermaid
stateDiagram-v2
    Decode --> InputPause: field incomplete
    InputPause --> Decode: retain bits; accept next chunk
    Decode --> OutputPause: destination or collection window full
    OutputPause --> Decode: unread current-call whole bytes; reoffer suffix
    Decode --> MemberEnd: validate padding and unread tail
    MemberEnd --> Decode: reset for next member
```

Public error conversion and lifecycle rules remain in
[the decoder API and state machine](decompressor.md). Boundary tests exercise
stored recognition, transfer, history wrap, concatenation, limits and read-ahead.

## Known gaps

- Recognition covers empty members and one raw block plus terminator; metadata
  and mixed/multiple data blocks use the full driver.
- Collection requires a fresh workspace and destination; transfer gives the
  caller a power-of-two allocation and leaves no history window for reuse.
- Appended and reused Vec output initializes newly exposed destination slices.
- Linear slice history covers only the first member of a one-call slice
  operation; sessions and later concatenated members deliver from the ring.
- The linear and ring command loops are separate instantiations, which adds
  about 60 KiB of `.text` to a program that uses both `decompress_to_slice`
  and a ring path. Removing the ring code from the linear loop left its
  register allocation worse in one place: the second-level Huffman lookup of
  the three-symbol trivial-context literal batch. `mapsdatazrh` at q1, q5 and
  q9, whose literals often take that path, decodes about 2% slower through
  `decompress_to_slice` even though it executes 7% fewer instructions. 1 MiB
  text decodes 3-6% faster. The ring instantiations execute the same
  instructions as before (+0.1%) but measured 0.2-1.3% slower, and
  uninitialized output about 3% slower, which is at the edge of what the
  benchmark resolves.
- Small compressed streams still build entropy tables and session state.
