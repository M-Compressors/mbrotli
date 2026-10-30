# Decoder SIMD dispatch

The constructor validates and stores a backend. Private `decompressor::core`
dispatches before command loops and bulk copy stages, passing a concrete
`fearless_simd::Simd` token into generic helpers. Headers, raw blocks and
resumable parsing stages share scalar control flow.

The SIMD choice is the innermost of three compile-time selections.
`Stream::run` first fixes the sink type and whether the member decodes into
linear slice history (`run_stages::<O, LINEAR>`). Each of those state machines
then dispatches the backend at its command loop and copy stages, so every
backend is compiled once per instantiation.

```mermaid
flowchart LR
    Run[Stream::run] --> Machine[run_stages per sink type and LINEAR]
    Machine --> Backend[validated Backend]
    Backend[validated Backend] --> Dispatch[dispatch outside command or copy loop]
    Dispatch --> Control[serial Huffman and command dependencies]
    Dispatch --> Copy[16/32-byte array snapshots]
    Control --> State[shared output, progress, limits and errors]
    Copy --> State
```

The dispatch gives the command loop its backend's target features: the bit
operations compile to BMI2 shifts and masks where available, and the short
copies are fixed-size array moves (`copy_chunk`) that those features turn into
one or two vector loads and stores. Copies load the complete source before
storing and accept unaligned initialized slices. One test of the later window
against the last start that fits covers both windows; a short boundary uses an
exact-length copy. Speculative writes remain within at most fifteen
unreachable ring bytes. Long overlapping expansions use fill, byte copying or
prefix doubling. Feature checks and virtual calls do not occur per byte or command.

[Native decompressor](decompressor.md) specifies wrap, overlap, dictionary and
error invariants. [Owned output](decoder-owned-output.md) specifies history growth
and transfer; those ownership rules are shared across backends.

## Verification and known gaps

Unit tests use a bytewise ring oracle and snapshot-copy cases. Differential tests
explicitly exercise fallback and every backend available on the host, checking
payload, consumed input, errors, limits and streaming progress.

Run the root `decompress` Criterion benchmark for retained slices, streaming and
backend comparisons; the separate [library comparison](../docs/benchmarking.md)
measures cold owned APIs. Profile with `hotpath` before changing these kernels.

Huffman construction and context-map transforms remain scalar. Backend tests
cannot validate instruction sets absent from their execution host; compilation
alone does not establish runtime correctness or speed.
