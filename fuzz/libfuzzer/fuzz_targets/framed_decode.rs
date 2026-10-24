//! libFuzzer adapter for [`mbrotli_afl::framed_targets::framed_decode`], the body the AFL
//! binary of the same name runs.

#![no_main]

use mbrotli_afl::Context;
use std::sync::LazyLock;

static CONTEXT: LazyLock<Context> = LazyLock::new(Context::default);

libfuzzer_sys::fuzz_target!(|data: &[u8]| mbrotli_afl::framed_targets::framed_decode(
    &CONTEXT, data
));
