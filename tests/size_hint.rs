#![cfg(feature = "compression")]
#![cfg(not(feature = "no_std"))]

//! A session of unknown length infers its size hint the way C's streaming
//! entry point does.
//!
//! `BrotliEncoderCompressStream` leaves `BROTLI_PARAM_SIZE_HINT` at zero only
//! until it first encodes: right before that, `UpdateSizeHint` sets it to the
//! bytes it holds plus the caller's remaining input. Qualities four to nine
//! choose their match finder and literal context modelling from that hint, so
//! a stream whose first encoding sees a mebibyte or more is a different stream
//! from one that assumes nothing. Async adapters hit this on every response:
//! they build an encoder per body without its length, then hand it the whole
//! body in one call.
//!
//! Every case drives mbrotli and C with the same sequence of calls and no
//! declared size, and requires identical bytes.

mod support;

use google_brotli_ffi as ffi;
use mbrotli::{Compressor, EncoderStatus, Operation, Quality, StreamConfig};
use support::{c_decompress, encoder, vendor_file};

/// Window every case in this file uses.
const LGWIN: u8 = 22;

/// Text past the one-mebibyte threshold the matcher choice turns on.
fn large_text() -> Vec<u8> {
    let mut text = Vec::new();
    for name in ["lcet10.txt", "plrabn12.txt", "alice29.txt", "asyoulik.txt"] {
        text.extend_from_slice(&vendor_file(name));
    }
    assert!(text.len() > 1 << 20, "the corpus must cross the threshold");
    text
}

fn c_operation(operation: Operation) -> ffi::BrotliEncoderOperation {
    match operation {
        Operation::Process => ffi::BROTLI_OPERATION_PROCESS,
        Operation::Flush => ffi::BROTLI_OPERATION_FLUSH,
        Operation::Finish => ffi::BROTLI_OPERATION_FINISH,
    }
}

/// Feeds `calls` to the C encoder with no size hint, each call repeated until
/// it has taken its input and delivered what it owes.
fn c_calls(quality: Quality, calls: &[(&[u8], Operation)]) -> Vec<u8> {
    let total: usize = calls.iter().map(|(input, _)| input.len()).sum();
    let mut output = vec![0u8; total * 2 + 4096 + 64 * calls.len()];
    let mut written = 0usize;
    unsafe {
        let state = ffi::BrotliEncoderCreateInstance(None, None, std::ptr::null_mut());
        assert!(!state.is_null(), "the C encoder could not be created");
        for (parameter, value) in [
            (ffi::BROTLI_PARAM_QUALITY, u32::from(quality.get())),
            (ffi::BROTLI_PARAM_LGWIN, u32::from(LGWIN)),
        ] {
            assert_eq!(
                ffi::BrotliEncoderSetParameter(state, parameter, value),
                ffi::BROTLI_TRUE
            );
        }
        for &(input, operation) in calls {
            let mut available_in = input.len();
            let mut next_in = input.as_ptr();
            loop {
                let mut available_out = output.len() - written;
                let mut next_out = output.as_mut_ptr().add(written);
                let ok = ffi::BrotliEncoderCompressStream(
                    state,
                    c_operation(operation),
                    &raw mut available_in,
                    &raw mut next_in,
                    &raw mut available_out,
                    &raw mut next_out,
                    std::ptr::null_mut(),
                );
                assert_eq!(ok, ffi::BROTLI_TRUE, "the C encoder failed");
                written = output.len() - available_out;
                if available_in == 0 && ffi::BrotliEncoderHasMoreOutput(state) != ffi::BROTLI_TRUE {
                    break;
                }
            }
        }
        assert_eq!(ffi::BrotliEncoderIsFinished(state), ffi::BROTLI_TRUE);
        ffi::BrotliEncoderDestroyInstance(state);
    }
    output.truncate(written);
    output
}

/// Feeds `calls` to an owned session of unknown length through `buffer`-sized
/// output slices, each call repeated until it has taken its input and
/// delivered what it owes.
fn rust_calls(compressor: Compressor, calls: &[(&[u8], Operation)], buffer: usize) -> Vec<u8> {
    let mut session = compressor
        .into_session(StreamConfig::default())
        .expect("a legal stream");
    let mut output = Vec::new();
    let mut scratch = vec![0u8; buffer];
    for &(mut input, operation) in calls {
        loop {
            let progress = session
                .process(input, &mut scratch, operation)
                .expect("the session failed");
            input = &input[progress.consumed..];
            output.extend_from_slice(&scratch[..progress.produced]);
            if input.is_empty() && progress.status != EncoderStatus::NeedsOutput {
                break;
            }
        }
    }
    assert!(session.is_finished());
    output
}

/// Asserts mbrotli matches C for `calls` at `quality`, through a large and a
/// small output buffer, and that the stream decodes.
fn assert_matches_c(quality: Quality, calls: &[(&[u8], Operation)]) {
    let expected = c_calls(quality, calls);
    let input: Vec<u8> = calls
        .iter()
        .flat_map(|(input, _)| input.iter().copied())
        .collect();
    for buffer in [1 << 22, 4096] {
        let actual = rust_calls(encoder(quality, LGWIN), calls, buffer);
        assert!(
            actual == expected,
            "q{} through {buffer}-byte output: {} bytes, C {}",
            quality.get(),
            actual.len(),
            expected.len()
        );
    }
    assert_eq!(
        c_decompress(&expected, input.len()).as_deref(),
        Some(&input[..])
    );
}

/// C's `ComputeLgBlock` for the default block size at a 22-bit window.
fn input_block_bits(quality: Quality) -> u32 {
    match quality.get() {
        0..=3 => 14,
        4..=8 => 16,
        _ => 18,
    }
}

/// Qualities whose output depends on the size hint, plus their neighbours.
const QUALITIES: [Quality; 6] = [
    Quality::Q3,
    Quality::Q4,
    Quality::Q5,
    Quality::Q6,
    Quality::Q9,
    Quality::Q10,
];

#[test]
fn a_whole_body_in_one_process_call_selects_the_large_input_matcher() {
    let text = large_text();
    for quality in QUALITIES {
        assert_matches_c(
            quality,
            &[(&text, Operation::Process), (&[], Operation::Finish)],
        );
    }
}

#[test]
fn a_whole_body_in_one_finish_call_selects_the_large_input_matcher() {
    let text = large_text();
    for quality in QUALITIES {
        assert_matches_c(quality, &[(&text, Operation::Finish)]);
    }
}

#[test]
fn staged_bytes_count_toward_the_hint_of_the_call_that_encodes_first() {
    // The first call stages less than a block and encodes nothing; the hint
    // is taken when the second call fills one, from both calls together.
    let text = large_text();
    let (head, tail) = text.split_at(10_000);
    for quality in [Quality::Q4, Quality::Q5] {
        assert_matches_c(
            quality,
            &[
                (head, Operation::Process),
                (tail, Operation::Process),
                (&[], Operation::Finish),
            ],
        );
    }
}

#[test]
fn a_block_filled_at_the_end_of_a_call_fixes_the_hint_at_that_block() {
    // C encodes as soon as a block is full, even with no input after it, so
    // a first call of exactly one block pins a small hint for the stream.
    let text = large_text();
    for quality in [Quality::Q4, Quality::Q5, Quality::Q9] {
        let block = 1usize << input_block_bits(quality);
        let (head, tail) = text.split_at(block);
        assert_matches_c(
            quality,
            &[
                (head, Operation::Process),
                (tail, Operation::Process),
                (&[], Operation::Finish),
            ],
        );
    }
}

#[test]
fn a_first_flush_fixes_the_hint_from_what_it_flushes() {
    let text = large_text();
    let (head, tail) = text.split_at(2_000);
    for quality in [Quality::Q4, Quality::Q6] {
        assert_matches_c(
            quality,
            &[
                (head, Operation::Flush),
                (tail, Operation::Process),
                (&[], Operation::Finish),
            ],
        );
    }
}

#[test]
fn an_empty_first_flush_leaves_the_hint_open() {
    let text = large_text();
    for quality in [Quality::Q4, Quality::Q5] {
        assert_matches_c(
            quality,
            &[
                (&[], Operation::Flush),
                (&text, Operation::Process),
                (&[], Operation::Finish),
            ],
        );
    }
}

#[test]
fn short_bodies_still_match_after_the_hint_is_inferred() {
    let text = large_text();
    for len in [0, 1, 100, 1121, 2048, 2049, 70_000] {
        for quality in QUALITIES {
            assert_matches_c(
                quality,
                &[(&text[..len], Operation::Process), (&[], Operation::Finish)],
            );
        }
    }
}

#[test]
fn a_reused_compressor_infers_each_streams_hint_afresh() {
    let text = large_text();
    for quality in [Quality::Q4, Quality::Q5] {
        let mut compressor = encoder(quality, LGWIN);
        for len in [text.len(), 1121, text.len()] {
            let calls: &[(&[u8], Operation)] =
                &[(&text[..len], Operation::Process), (&[], Operation::Finish)];
            let mut session = compressor
                .into_session(StreamConfig::default())
                .expect("a legal stream");
            let mut output = vec![0u8; len * 2 + 4096];
            let mut produced = 0;
            for &(input, operation) in calls {
                let progress = session
                    .process(input, &mut output[produced..], operation)
                    .expect("the session failed");
                assert_eq!(progress.consumed, input.len());
                produced += progress.produced;
            }
            assert!(session.is_finished());
            output.truncate(produced);
            assert!(
                output == c_calls(quality, calls),
                "q{} reused for {len} bytes",
                quality.get()
            );
            compressor = session.into_compressor();
        }
    }
}
