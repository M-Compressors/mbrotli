#![cfg(feature = "decompression")]
//! Decoding into uninitialized memory against the initialized-slice APIs.
//!
//! `process_uninit` and `decompress_to_uninit` always deliver through the
//! ring, never using the destination as history. They must agree with
//! `process` and `decompress_to_slice` on every byte, count, status and error,
//! and must not write a byte past what they report.

mod support;

use std::mem::MaybeUninit;

use mbrotli::{
    DecodeError, DecodeOperation, DecodeProgress, DecodeStreamConfig, DecoderStatus, Decompressor,
};
use support::{Rng, c_compress};

/// Marks destination bytes the decoder must not have written.
const SENTINEL: u8 = 0xa5;

/// Mixed text, runs and noise, so streams carry literals, copies and
/// dictionary references.
fn payload(len: usize) -> Vec<u8> {
    let mut rng = Rng::new(0xfedc_ba98_7654_3210);
    let mut data = Vec::with_capacity(len);
    while data.len() < len {
        match rng.next_u8() % 3 {
            0 => data.extend_from_slice(b"the quick brown fox jumps over the lazy dog. "),
            1 => data.extend(std::iter::repeat_n(rng.next_u8(), 97)),
            _ => data.extend(rng.bytes(61, 256)),
        }
    }
    data.truncate(len);
    data
}

/// Reads bytes the test itself initialized or the decoder reported written.
fn read(bytes: &[MaybeUninit<u8>]) -> Vec<u8> {
    // SAFETY: callers pass only the reported prefix or sentinel-filled bytes,
    // all of which are initialized.
    bytes
        .iter()
        .map(|byte| unsafe { byte.assume_init() })
        .collect()
}

fn untouched(bytes: &[MaybeUninit<u8>]) -> bool {
    read(bytes).iter().all(|&byte| byte == SENTINEL)
}

/// Every call's outcome: its progress, or the failure's error and counts.
type Outcome = Result<DecodeProgress, (String, usize, usize)>;

/// Decodes `input` fed in `chunk` pieces into `window`-sized outputs, through
/// the initialized or the uninitialized method, until it finishes or fails.
fn stream(input: &[u8], chunk: usize, window: usize, uninit: bool) -> (Vec<u8>, Vec<Outcome>) {
    let mut decoder = Decompressor::new(Default::default()).expect("a decoder");
    let mut session = decoder
        .start(DecodeStreamConfig::default())
        .expect("starts");
    let mut initialized = vec![0u8; window];
    let mut uninitialized = vec![MaybeUninit::new(SENTINEL); window];
    let mut output = Vec::new();
    let mut calls = Vec::new();
    let mut offset = 0;
    loop {
        let end = (offset + chunk).min(input.len());
        let operation = if end == input.len() {
            DecodeOperation::Finish
        } else {
            DecodeOperation::Process
        };
        let result = if uninit {
            let result = session.process_uninit(&input[offset..end], &mut uninitialized, operation);
            let produced = match &result {
                Ok(progress) => progress.produced,
                Err(failure) => failure.produced,
            };
            output.extend(read(&uninitialized[..produced]));
            assert!(
                untouched(&uninitialized[produced..]),
                "wrote past `produced`"
            );
            uninitialized.fill(MaybeUninit::new(SENTINEL));
            result
        } else {
            let result = session.process(&input[offset..end], &mut initialized, operation);
            let produced = match &result {
                Ok(progress) => progress.produced,
                Err(failure) => failure.produced,
            };
            output.extend_from_slice(&initialized[..produced]);
            result
        };
        match result {
            Ok(progress) => {
                offset += progress.consumed;
                calls.push(Ok(progress));
                if progress.status == DecoderStatus::Finished {
                    return (output, calls);
                }
            }
            Err(failure) => {
                calls.push(Err((
                    failure.error.to_string(),
                    failure.consumed,
                    failure.produced,
                )));
                return (output, calls);
            }
        }
    }
}

#[test]
fn process_uninit_matches_process_across_qualities_and_windows() {
    let data = payload(200_000);
    for quality in [0, 1, 5, 9, 11] {
        let compressed = c_compress(quality, 22, &data);
        for window in [1, 127, 1 << 16, 1 << 20] {
            for chunk in [31, 1 << 16] {
                let expected = stream(&compressed, chunk, window, false);
                assert_eq!(expected.0, data, "q{quality}: process");
                assert_eq!(
                    stream(&compressed, chunk, window, true),
                    expected,
                    "q{quality} window {window} chunk {chunk}"
                );
            }
        }
    }
}

#[test]
fn process_uninit_reports_a_corrupt_stream_with_initialized_progress() {
    let data = payload(50_000);
    let mut compressed = c_compress(5, 22, &data);
    let middle = compressed.len() / 2;
    compressed[middle] ^= 0xff;
    compressed.truncate(middle + 64);
    for window in [127, 1 << 20] {
        let expected = stream(&compressed, 1 << 16, window, false);
        assert!(expected.1.last().is_some_and(Result::is_err));
        assert_eq!(stream(&compressed, 1 << 16, window, true), expected);
    }
}

#[test]
fn owned_process_uninit_decodes_the_stream() {
    let data = payload(100_000);
    let compressed = c_compress(9, 22, &data);
    let mut session = Decompressor::new(Default::default())
        .expect("a decoder")
        .into_session(DecodeStreamConfig::default())
        .expect("starts");
    let mut buffer = vec![MaybeUninit::uninit(); 4096];
    let mut output = Vec::new();
    let mut input = compressed.as_slice();
    loop {
        let progress = session
            .process_uninit(input, &mut buffer, DecodeOperation::Finish)
            .expect("decodes");
        input = &input[progress.consumed..];
        output.extend(read(&buffer[..progress.produced]));
        if progress.status == DecoderStatus::Finished {
            break;
        }
    }
    assert_eq!(output, data);
    assert!(session.into_decompressor().decompress(&compressed).is_ok());
}

#[test]
fn decompress_to_uninit_matches_decompress_to_slice() {
    let mut decoder = Decompressor::new(Default::default()).expect("a decoder");
    for len in [0, 1, 1000, 300_000] {
        let data = payload(len);
        for quality in [0, 5, 11] {
            let compressed = c_compress(quality, 22, &data);
            let mut uninitialized = vec![MaybeUninit::new(SENTINEL); len + 16];
            let written = decoder
                .decompress_to_uninit(&compressed, &mut uninitialized)
                .expect("decodes");
            assert_eq!(written, len);
            assert_eq!(
                read(&uninitialized[..written]),
                data,
                "q{quality} len {len}"
            );
            assert!(untouched(&uninitialized[written..]));
        }
    }
}

#[test]
fn decompress_to_uninit_copies_a_stored_member_that_fits() {
    let mut rng = Rng::new(0x5eed);
    let data = rng.bytes(10_000, 256);
    let compressed = c_compress(9, 22, &data);
    let mut decoder = Decompressor::new(Default::default()).expect("a decoder");

    let mut room = vec![MaybeUninit::new(SENTINEL); data.len() + 16];
    assert_eq!(
        decoder.decompress_to_uninit(&compressed, &mut room).ok(),
        Some(data.len())
    );
    assert_eq!(read(&room[..data.len()]), data);
    assert!(untouched(&room[data.len()..]));

    // One byte short, the session path reports how much fitted.
    let mut short = vec![MaybeUninit::new(SENTINEL); data.len() - 1];
    assert!(matches!(
        decoder.decompress_to_uninit(&compressed, &mut short),
        Err(DecodeError::OutputTooSmall { written }) if written == data.len() - 1
    ));
    assert_eq!(read(&short), &data[..data.len() - 1]);
}

#[test]
fn decompress_to_uninit_reports_the_same_errors_as_decompress_to_slice() {
    let data = payload(10_000);
    let compressed = c_compress(5, 22, &data);
    let mut decoder = Decompressor::new(Default::default()).expect("a decoder");

    let mut short = vec![MaybeUninit::new(SENTINEL); 100];
    assert!(matches!(
        decoder.decompress_to_uninit(&compressed, &mut short),
        Err(DecodeError::OutputTooSmall { written: 100 })
    ));
    assert_eq!(read(&short), &data[..100]);

    let mut trailing = compressed.clone();
    trailing.push(0);
    let mut room = vec![MaybeUninit::uninit(); data.len()];
    let mut slice = vec![0; data.len()];
    let expected = decoder.decompress_to_slice(&trailing, &mut slice);
    assert!(matches!(expected, Err(DecodeError::TrailingData { .. })));
    assert_eq!(
        decoder
            .decompress_to_uninit(&trailing, &mut room)
            .map_err(|error| error.to_string()),
        expected.map_err(|error| error.to_string())
    );

    let truncated = &compressed[..compressed.len() - 1];
    assert!(matches!(
        decoder.decompress_to_uninit(truncated, &mut room),
        Err(DecodeError::UnexpectedEndOfInput)
    ));
    assert_eq!(
        decoder.decompress_to_uninit(&compressed, &mut room).ok(),
        Some(data.len())
    );
}
