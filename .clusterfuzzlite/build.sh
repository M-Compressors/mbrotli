#!/bin/bash -eu
# Builds the libFuzzer targets in fuzz/libfuzzer for ClusterFuzzLite.
#
# Each target is a three line adapter around a body in the AFL package's
# library, so a finding here replays through `cargo afl test` once its input is
# committed under fuzz/afl/regressions/<target>/.
#
# The stable targets are built without `experimental`, so the decoder and
# encoder they fuzz are the default surface a dependant gets. The experimental
# targets come from a second build in its own target directory; its copies of
# the stable targets are not shipped.

cd "$SRC/mbrotli"

# The C oracle is the pinned vendored Brotli, a submodule ClusterFuzzLite's
# own checkout leaves empty. The pin comes from the checked out commit.
if [ ! -f brotli-ffi/vendor/brotli/c/include/brotli/decode.h ]; then
    git config --global --add safe.directory '*'
    git submodule update --init --depth 1 brotli-ffi/vendor/brotli
fi

host=$(rustc -vV | sed -n 's/^host: //p')

# Under the coverage sanitizer the image's cargo wrapper replaces
# `cargo fuzz build` with a plain `cargo build --bins` run from `fuzz/`, which
# drops --fuzz-dir, --target-dir and --features and finds the root crate, which
# has no binaries. The coverage build is therefore a plain cargo build of the
# package: the image's RUSTFLAGS already carry `--cfg fuzzing` and the coverage
# instrumentation, and the wrapper's remap for the package's own relative
# source paths is repeated here. It stays unoptimized, as in the wrapper, to
# avoid malformed profile data.
if [ "$SANITIZER" = "coverage" ]; then
    profile=debug
    build() {
        (
            cd fuzz/libfuzzer
            RUSTFLAGS="$RUSTFLAGS --remap-path-prefix fuzz_targets=$PWD/fuzz_targets" \
                cargo build --bins "$@"
        )
    }
else
    profile="$host/release"
    # Debug assertions also turn on overflow checks, which AFL's builds have
    # too.
    build() {
        cargo fuzz build -O --debug-assertions --fuzz-dir fuzz/libfuzzer "$@"
    }
fi

ship() {
    local release="$1/$profile"
    for source in fuzz/libfuzzer/fuzz_targets/*.rs; do
        local target
        target=$(basename "$source" .rs)
        if [ -x "$release/$target" ] && [ ! -e "$OUT/$target" ]; then
            cp "$release/$target" "$OUT/"
        fi
    done
}

build --target-dir "$WORK/stable"
ship "$WORK/stable"
build --target-dir "$WORK/experimental" --features experimental
ship "$WORK/experimental"

# Seed corpora: the generated AFL corpus each target's input model reads, plus
# its committed regressions. Seeds above 64 KiB are left out; every target caps
# its payload at 128 KiB or less, and small seeds keep the first runs fast.
fuzz/afl/prepare-seeds.sh
fuzz/afl/prepare-decoder-seeds.sh

seeds_for() {
    case "$1" in
        decode_roundtrip | differential_c | encoder_session | output_capacity | \
            parameter_parsing | params_roundtrip | simd_equivalence | \
            streaming_equivalence) echo fuzz/afl/seeds/params ;;
        decode_io_limits | decode_streaming | decoder_session | decompress)
            echo fuzz/afl/seeds/decoder ;;
        dictionary) echo fuzz/afl/seeds/dictionary ;;
        large_window) echo fuzz/afl/seeds/large_window ;;
        serialized_dictionary) echo fuzz/afl/seeds/serialized ;;
    esac
}

for binary in "$OUT"/*; do
    [ -x "$binary" ] || continue
    target=$(basename "$binary")
    corpus="$WORK/corpus/$target"
    rm -rf "$corpus"
    mkdir -p "$corpus"
    # Prefixes keep a seed and a regression with the same name apart.
    for directory in $(seeds_for "$target") "fuzz/afl/regressions/$target"; do
        [ -d "$directory" ] || continue
        prefix=$(basename "$(dirname "$directory")")
        find "$directory" -maxdepth 1 -type f -size -65537c -print0 |
            while IFS= read -r -d '' path; do
                cp "$path" "$corpus/$prefix-$(basename "$path")"
            done
    done
    if [ -n "$(ls -A "$corpus")" ]; then
        (cd "$corpus" && zip -q "$OUT/${target}_seed_corpus.zip" ./*)
    fi
done

cp fuzz/afl/dictionaries/framed.dict "$OUT/framed_decode.dict"
