# Private common codec primitives

`src/shared` is a private crate-root module. It replaces
`src/compressor/core/shared`; both codecs import it directly. It is not a public
re-export or a second implementation. Existing bit writer, entropy construction,
match scans, command/metablock representations and ring buffer keep their encoder
behavior and tests. Binary dictionary/transform data is stored once here.

```mermaid
graph LR
    Encoder[compressor::core: fast / greedy / hq] --> Shared[crate::shared]
    Decoder[decompressor::core] --> Shared
    Shared --> Format[format constants / context tables]
    Shared --> Words[dictionary word bytes / borrowed Transform]
    Shared --> Entropy[encoder entropy, command, block and bit writers]
    Shared --> Baseline[baseline: compile-time SIMD level, prefetch]
    Entropy --> Scan[scan: 16-lane mask walks]
    Scan --> Baseline
    Shared --> Decode[decode_dictionary / experimental decode_serialized]
    RFC[compressor::core::rfc9841] --> Words
    Entropy -. encoder command integration .-> RFC
    Dictionary[public dictionary facade] -->|decompression| Decode
    Dictionary -->|compression| RFC
```

The decoder uses wire constants, context tables, built-in words, shared borrowed
transform application and decode-only dictionary storage. It owns its own bit
reader, Huffman reader, window/history and parser state in `decompressor::core`;
encoder bit output and match-search types are not reused as decoder state.

The encoder's experimental transform-list ownership and index construction stay
under `compressor::core::rfc9841`, but application delegates to the same borrowed
`Transform` that serialized-dictionary decoding uses. Built-in words in the
decoder take `apply_builtin` instead: every built-in prefix and suffix is at
most eight bytes and a word at most 24, so it copies them as fixed 8- and
32-byte moves from padded tables into the 541-byte scratch, where the bytes
past the logical end are overwritten by the suffix or never read. That replaced
three variable-length `memcpy` calls per dictionary reference (decoding
dictionary-heavy text 3-8% fewer instructions, up to 12% faster at quality
eleven); an out-of-line exact copy covers the last words of the table, whose
32-byte read would run past it. A test compares it with `Transform::apply` for
all 121 transforms. The shared module still contains encoder-only
primitives: command integration depends on private RFC9841 encoder types. This
is a crate-private dependency, not a fully independent reusable package. Backend
selection remains at each public codec's construction boundary; encoder SIMD
dispatch stays at the encoders' block boundaries in `compressor::core`.

```mermaid
sequenceDiagram
    participant Codec
    participant View as borrowed word/transform view
    participant Shared as shared::dictionary::Transform
    participant Scratch as caller-owned fixed scratch
    Codec->>View: resolve word and transform index
    View-->>Codec: borrowed bytes and validated operation
    Codec->>Shared: apply(word, scratch)
    Shared->>Scratch: prefix + transformed word + suffix
    Shared-->>Codec: actual transformed length
```

Transform operations are byte-oriented format rules, not general Unicode case
conversion. Incomplete sequences use initialized guard space in the fixed scratch;
suffix output overwrites any casing writes beyond the logical word. Custom shift
operations and custom serialized representations compile only with `experimental`.
No transformed dictionary is materialized. Borrowed inputs outlive one application,
and no core keeps caller pointers between operations.

`shared::baseline` and `shared::scan` (compression only) give code outside the
encoders' dispatched SIMD entries a vector level without detection. Handing
such code the encoder's runtime level would make every vector operation an
out-of-line call, so `baseline::run` hands a `Kernel` (a value with a generic
`run<S: Simd>`) the level every build of the target has: `Sse2` from
`Level::baseline().as_sse2()` on x86, `Neon` on AArch64, otherwise whatever
`Level::baseline()` is. The selection is a constant and folds away.
`baseline::prefetch` is the reference's `PREFETCH_L1`, a read hint into L1:
`branches::prefetch_read_data::<T, 0>`, which keeps the inline assembly out of
this crate. It emits `prefetcht0` on x86-64 and x86 with SSE, `prfm
pldl1keep` on AArch64, the targets' own prefetch on riscv64 with `zicbop`,
s390x and PowerPC, and the LLVM intrinsic on nightly; elsewhere it does
nothing. The crate's `std` feature enables `branches/std`; without it,
`branches` builds its unused `abort` on `core::intrinsics::abort_immediate`
under any nightly, which older nightlies lack. A `no_std` build on such a
nightly still fails inside `branches`; stable is unaffected. There is no
write variant: the hinted bucket is read by the next
search before its store, and a line read by the encoder's single thread
arrives exclusive, so the store needs no second request. `scan` holds the sixteen-lane mask walks the prefix-code builders use
([fast-encoder.md](fast-encoder.md) §6.1); each is tested on the scalar,
baseline and detected levels against the plain loop.

```mermaid
flowchart LR
    Caller["huffman / histogram / hashers (no target_feature)"] --> Run["baseline::run(kernel)"]
    Run -->|x86| SSE2["kernel.run(Sse2)"]
    Run -->|AArch64| NEON["kernel.run(Neon)"]
    Run -->|other| Any["dispatch!(Level::baseline())"]
    Caller --> Pre["baseline::prefetch(&T)"]
    Pre --> B["branches::prefetch_read_data::<T, 0>"]
    B -->|x86 / x86-64| T0["prefetcht0"]
    B -->|AArch64| PLD["prfm pldl1keep"]
    B -->|unsupported target| Nop["no-op"]
```

`shared::fixed` (compression only) builds `Box<[T; N]>` tables:
`fixed_table(initial)` allocates through a `Vec` of exactly `N` entries, so a
zero fill reaches the allocator as a zeroed allocation, and
`fixed_table_from_vec(values, initial)` resizes an existing vector into one
without copying. The greedy matchers' dense and chain tables and the
high-quality cost model's histograms use it. A zero-valued table is built
with `vec!` rather than by collecting an iterator: `vec![0; n]` reaches
`alloc_zeroed` for every element type, while a collected `u32` table compiles
to an allocation plus an explicit `memset` (up to 1800× slower on a fresh
16 MiB table touched in its first page).

`grow_zeroed(buffer, len)` grows a reusable `Vec` workspace. An empty buffer is
allocated zeroed, so a large buffer most of which is never written costs no
writes; a buffer that already holds data grows with `Vec::resize`, which an
allocator may perform in place, and never shrinks. Greedy, high-quality and fast
encoder output storage and the fast encoder's hash table use it. Buffers that
are sized per block and written in full before they are read are resized
without a preceding `clear()`, so only newly exposed elements are zero-filled.

```mermaid
graph LR
    Fixed[shared::fixed] --> Greedy[greedy dense / chain tables]
    Fixed --> Cost[hq ZopfliCostModel histograms and literal prices]
    Vec["vec![initial; N]"] --> Boxed["into_boxed_slice → Box<[T; N]>"]
    Grow["grow_zeroed(buffer, len)"] --> Empty{"buffer empty?"}
    Empty -->|yes| Calloc["vec![0; len]: zeroed allocation"]
    Empty -->|no| Resize["Vec::resize: zero only the new tail"]
```

Known gap: encoder-specific primitives remain colocated with format-neutral data;
there is no standalone common-data crate. This keeps existing private dependencies
and public API identities intact while making common data accessible to both codecs.

Codec gates remove unused private primitives as well as public APIs. Encoder
search/hash/entropy modules require `compression`; decoder dictionary modules
require `decompression`. Built-in words and format tables are common. Public
decode dictionary types live in `src/dictionary/decode.rs`, with the root
facade retaining prepared dictionary exports when compression is enabled.
Shared configuration and finish errors live in private root modules; see
[codec feature boundaries](codec-features.md) for their ownership diagram.
