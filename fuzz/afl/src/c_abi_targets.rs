//! The `mbrotli-ffi` C ABI, called through its exported functions.
//!
//! Input layout: byte 0 is a quality in `-2..=13` and byte 1 a window in
//! `0..=31`, so both edges of each accepted range are reached; byte 2 picks
//! the output capacity; the rest is the payload, capped at [`MAX_PAYLOAD`].

use crate::decode_oracle::{self, Outcome};
use crate::{MAX_PAYLOAD, cap};
use google_brotli_ffi as ffi;
use mbrotli_ffi::*;
use std::ffi::c_int;
use std::mem::MaybeUninit;

/// Bytes of a fuzz input that select parameters rather than payload.
const HEADER_LEN: usize = 3;

/// Output budget for re-decoding a stream Google rejected, so a malformed
/// stream that expands enormously cannot stall an iteration.
const MAX_OUTPUT: usize = 1 << 20;

/// Calls `mbrotli_compress` with an output of `capacity` bytes.
fn compress(
    input: &[u8],
    capacity: usize,
    quality: c_int,
    lgwin: c_int,
) -> (MbrotliResult, Vec<u8>) {
    let mut output = vec![0xa5; capacity];
    let mut len = capacity;
    // SAFETY: both buffers are live, disjoint and have the stated lengths.
    let status = unsafe {
        mbrotli_compress(
            input.as_ptr(),
            input.len(),
            output.as_mut_ptr(),
            &mut len,
            quality,
            lgwin,
        )
    };
    output.truncate(len);
    (status, output)
}

/// Calls `mbrotli_decompress` with an output of `capacity` bytes.
fn decompress(input: &[u8], capacity: usize) -> (MbrotliResult, Vec<u8>) {
    let mut output = vec![0xa5; capacity];
    let mut len = capacity;
    // SAFETY: both buffers are live, disjoint and have the stated lengths.
    let status =
        unsafe { mbrotli_decompress(input.as_ptr(), input.len(), output.as_mut_ptr(), &mut len) };
    output.truncate(len);
    (status, output)
}

/// Google's `BrotliEncoderCompress` with an output of `capacity` bytes.
fn google_compress(input: &[u8], capacity: usize, quality: c_int, lgwin: c_int) -> Option<Vec<u8>> {
    let mut output = vec![0; capacity];
    let mut len = capacity;
    // SAFETY: both buffers are live and have the stated lengths.
    let accepted = unsafe {
        ffi::BrotliEncoderCompress(
            quality,
            lgwin,
            ffi::BROTLI_MODE_GENERIC,
            input.len(),
            input.as_ptr(),
            &mut len,
            output.as_mut_ptr(),
        )
    };
    (accepted == ffi::BROTLI_TRUE).then(|| {
        output.truncate(len);
        output
    })
}

/// Whether the C oracle's stream is comparable byte for byte on this host.
///
/// Qualities 10 and 11 price candidates in floating point; clang contracts
/// the C library's multiply-adds into FMA on aarch64, which moves rare ties.
fn google_is_exact(quality: c_int) -> bool {
    quality < 10 || !cfg!(target_arch = "aarch64")
}

/// The C ABI must validate parameters, match Google's one-shot API at any
/// output capacity, round-trip, and agree with Google's decoder on arbitrary
/// bytes.
pub fn c_abi(_ctx: &crate::Context, input: &[u8]) {
    sessions(input);
    let (header, payload) = input.split_at(input.len().min(HEADER_LEN));
    let payload = cap(payload);
    let byte = |index: usize| header.get(index).copied().unwrap_or(0);
    let quality = c_int::from(byte(0) % 16) - 2;
    let lgwin = c_int::from(byte(1) % 32);
    let bound = mbrotli_compress_bound(payload.len());
    assert!(bound > payload.len() && bound <= payload.len() + 2 + 4 * (MAX_PAYLOAD >> 14) + 4);

    let (status, stream) = compress(payload, bound, quality, lgwin);
    let valid = (0..=11).contains(&quality) && (10..=24).contains(&lgwin);
    if !valid {
        assert_eq!(
            status,
            MbrotliResult::InvalidParameter,
            "q{quality} w{lgwin}"
        );
        assert!(stream.is_empty());
    } else {
        assert_eq!(status, MbrotliResult::Ok, "the bound must always suffice");
        let (status, restored) = decompress(&stream, payload.len());
        assert_eq!(status, MbrotliResult::Ok);
        assert_eq!(restored, payload, "round trip");
        if !payload.is_empty() {
            let (status, prefix) = decompress(&stream, payload.len() - 1);
            assert_eq!(status, MbrotliResult::OutputTooSmall);
            assert!(prefix.is_empty(), "output_len is zeroed on failure");
        }
        if google_is_exact(quality) {
            assert_eq!(
                Some(&stream),
                google_compress(payload, bound, quality, lgwin).as_ref()
            );
            // Any capacity, below or above the stream: same outcome and bytes.
            let capacity = match byte(2) % 4 {
                0 => stream.len(),
                1 => stream.len().saturating_sub(1),
                2 => bound - 1,
                _ => usize::from(byte(2)) * 4,
            };
            let (status, ours) = compress(payload, capacity, quality, lgwin);
            match google_compress(payload, capacity, quality, lgwin) {
                Some(theirs) => assert_eq!(
                    (status, ours),
                    (MbrotliResult::Ok, theirs),
                    "capacity {capacity}"
                ),
                None => assert_eq!(status, MbrotliResult::OutputTooSmall, "capacity {capacity}"),
            }
        }
    }

    // The payload as compressed input, against Google's streaming decoder
    // with large windows enabled, which also reports what it consumed.
    let capacity = usize::from(byte(2)) * 256;
    let (status, ours) = decompress(payload, capacity);
    match decode_oracle::decode(payload, capacity, None) {
        Outcome::Success {
            payload: theirs,
            consumed,
        } if consumed == payload.len() => {
            assert_eq!((status, ours), (MbrotliResult::Ok, theirs));
        }
        // Trailing bytes after a complete stream, or a malformed stream. When
        // the malformation lies past the output capacity, the decoder may run
        // out of room first; a larger buffer must then still be refused.
        Outcome::Success { .. } | Outcome::Invalid | Outcome::NeedsInput => match status {
            MbrotliResult::Error => {}
            MbrotliResult::OutputTooSmall => {
                let (status, _) = decompress(payload, MAX_OUTPUT);
                assert!(
                    matches!(status, MbrotliResult::Error | MbrotliResult::OutputTooSmall),
                    "a stream Google rejects decoded as {status:?}"
                );
            }
            status => panic!("a stream Google rejects returned {status:?}"),
        },
        // Google stops once the output is full; the stream may still turn out
        // to be malformed right after, which this decoder may see first.
        Outcome::OutputBudget => {
            assert!(matches!(
                status,
                MbrotliResult::OutputTooSmall | MbrotliResult::Error
            ));
        }
        Outcome::AllocationFailure | Outcome::AttachmentRejected | Outcome::UnsupportedWindow => {}
    }
}

/// Bounded session round-trip through tiny uninitialized buffers, including
/// reuse. Input bytes select quality and output width; no pointer is arbitrary.
fn sessions(input: &[u8]) {
    let quality = c_int::from(input.first().copied().unwrap_or(0) % 10);
    let width = 1 + usize::from(input.get(1).copied().unwrap_or(0) % 64);
    let payload = &input[input.len().min(2)..input.len().min(514)];
    // SAFETY: live exclusive handles, disjoint valid buffers/counts, matching
    // destruction. Only the output prefix reported initialized is read.
    unsafe {
        let encoder = mbrotli_encoder_session_create(quality, 22);
        let decoder = mbrotli_decoder_session_create();
        assert!(!encoder.is_null() && !decoder.is_null());
        for source in [payload, &[]] {
            let mut wire = Vec::new();
            let mut remaining = source;
            loop {
                let mut output = [MaybeUninit::<u8>::uninit(); 64];
                let (mut read, mut written) = (remaining.len(), width);
                let status = mbrotli_encoder_session_process(
                    encoder,
                    remaining.as_ptr(),
                    &mut read,
                    output.as_mut_ptr().cast(),
                    &mut written,
                    MbrotliOperation::Finish as c_int,
                );
                assert!(read <= remaining.len() && written <= width);
                remaining = &remaining[read..];
                wire.extend(output[..written].iter().map(|byte| byte.assume_init()));
                assert!(wire.len() <= 4096);
                if status == MbrotliResult::Finished {
                    break;
                }
                assert_eq!(status, MbrotliResult::NeedsOutput);
                assert!(read + written > 0);
            }
            assert!(remaining.is_empty());
            let mut restored = Vec::new();
            remaining = &wire;
            loop {
                let mut output = [MaybeUninit::<u8>::uninit(); 64];
                let (mut read, mut written) = (remaining.len(), width);
                let status = mbrotli_decoder_session_process(
                    decoder,
                    remaining.as_ptr(),
                    &mut read,
                    output.as_mut_ptr().cast(),
                    &mut written,
                    MbrotliOperation::Finish as c_int,
                );
                assert!(read <= remaining.len() && written <= width);
                remaining = &remaining[read..];
                restored.extend(output[..written].iter().map(|byte| byte.assume_init()));
                assert!(restored.len() <= source.len());
                if status == MbrotliResult::Finished {
                    break;
                }
                assert_eq!(status, MbrotliResult::NeedsOutput);
                assert!(read + written > 0);
            }
            assert!(remaining.is_empty());
            assert_eq!(restored, source);
            assert_eq!(
                decompress(&wire, source.len()),
                (MbrotliResult::Ok, source.to_vec())
            );
            assert_eq!(mbrotli_encoder_session_reinit(encoder), MbrotliResult::Ok);
            assert_eq!(mbrotli_decoder_session_reinit(decoder), MbrotliResult::Ok);
        }
        mbrotli_encoder_session_destroy(encoder);
        mbrotli_decoder_session_destroy(decoder);
    }
}
