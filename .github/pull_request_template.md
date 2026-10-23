## Summary

<!-- What does this change and why? Link the issue it addresses (Fixes #...). -->

## Byte identity

<!-- For changes to compression: confirm output still matches Google Brotli
     v1.2.0 under equivalent streaming settings, or explain why this path is
     outside the guarantee. Otherwise write "N/A". -->

## Performance

<!-- For performance-sensitive changes: command, corpus, machine, and
     before/after numbers for both speed and compressed size. Otherwise "N/A". -->

## Checklist

- [ ] `cargo fmt --all -- --check`
- [ ] `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings`
- [ ] `cargo test --workspace --all-features --locked`
- [ ] `cargo test --workspace --locked`
- [ ] `cargo test --workspace --features experimental --locked`
- [ ] `scripts/check_codec_features.py` and `scripts/check_decoder_features.py`, if Cargo features changed
- [ ] New and changed functions are covered by tests (`cargo llvm-cov`); bug fixes include a regression test
- [ ] `fuzz/afl` checks, if fuzz targets or the public APIs they call changed
- [ ] `architecture/` specifications, diagrams and index updated
- [ ] `CHANGELOG.md` updated for user-visible changes
- [ ] No new `#[allow(..)]`; no edits to `brotli-ffi/vendor/`
