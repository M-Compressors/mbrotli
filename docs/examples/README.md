# Examples

The recipes below include complete programs and round-trip assertions. Examples
use the default `std`, compression, and decompression features unless stated
otherwise. The documentation workflow compiles and runs their Rust code against
the current checkout.

| Task | Recipe | Features / extra dependency |
| --- | --- | --- |
| Compress and decompress bytes | [First round trip](../getting-started.md#compress-and-decompress) | Default |
| Reuse codec and destination memory | [Reuse the workspace](../getting-started.md#reuse-the-workspace-and-output) | Default |
| Pick a quality | [Choose a quality first](../configuration.md#choose-a-quality-first) | Default |
| Write into a caller-owned slice | [Output buffers](../memory.md#output-buffers) | Default |
| Decode untrusted input with budgets | [Set limits for untrusted input](../decompression.md#set-limits-for-untrusted-input) | Default |
| Write a raw stream incrementally | [Stream through Write](../getting-started.md#stream-through-write) | Default |
| Drive a raw or framed encoder with tiny buffers | [Sans I/O compression](../sans-io-compression.md) | Default; `experimental` for frames |
| Decode arriving chunks and resource events | [Sans I/O decompression](../sans-io-decompression.md) | Default; `experimental` for frames |
| Read or write raw, parallel, and framed streams | [Read / Write I/O](../io.md) | Default; `experimental` for frames |
| Use scoped CPU workers | [Compressing a slice](../parallel.md#compressing-a-slice) | Default |
| Reuse a Rayon thread pool | [Running tasks with Rayon](../parallel.md#running-tasks-with-rayon) | Default + `rayon` |
| Stream through parallel workers | [Reader and writer adapters](../parallel.md#reader-and-writer-adapters) | Default |
| Package compressed and stored resources | [One container, two resources](../frames.md#one-container-two-resources) | `experimental` |
| Add resource names and write incrementally | [Write resources and metadata](../frames.md#write-resources-and-metadata) | `experimental` |
| Read just the selected resource | [Indexed resource reads](../frames.md#indexed-resource-reads) | `experimental` |

## Run from the repository

Initialize the C reference submodule used by development builds:

```sh
git submodule update --init --recursive
cargo run --release --example compress
```

The [parallel file example](../../examples/parallel.rs) uses caller-owned scoped
threads and disk staging. The destination must not already exist:

```sh
cargo run --release --example parallel -- input.bin output.br
```

For a parallel batch, all taken tasks must run or be dropped before finalization.
For a streaming adapter, keep workers running while the adapter blocks.
For writers, finish each resource and the enclosing stream or container explicitly.

## Verify the documented recipes

```sh
python3 scripts/docs.py test-examples
```

This creates a temporary Cargo consumer under `target/`, depends on the local
crate with `experimental` enabled and on Rayon, and runs each fenced Rust program
from the recipe guides: getting started, configuration, buffers, decompression,
streaming, parallel, frames, Sans I/O compression/decompression, and the I/O
guide. It does not
exercise the codec with `--all-features`, because that would also enable `no_std`
and remove the std APIs these recipes demonstrate.
