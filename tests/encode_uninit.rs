#![cfg(feature = "compression")]
//! Encoding into uninitialized memory against the initialized-slice APIs.
//!
//! `process_uninit` and `compress_to_uninit` never run the fast qualities'
//! in-place bit writer, so they reach the stream through a different path
//! than `process` and `compress_to_slice` do whenever the destination has
//! room for a whole fragment. Both paths must agree on every byte, count,
//! status and error, and the uninitialized ones must not write a byte past
//! what they report.

mod support;

use std::mem::MaybeUninit;

use mbrotli::{
    Compressor, EncodeError, EncoderStatus, InputSize, Operation, Progress, Quality, StreamConfig,
};
use support::{IMPLEMENTED_QUALITIES, Rng, c_decompress, encoder};

/// Marks destination bytes the encoder must not have written.
const SENTINEL: u8 = 0xa5;

/// Output windows: single bytes, odd sizes, and room for whole fragments.
const WINDOWS: [usize; 4] = [1, 13, 4096, 1 << 20];

/// Which API a call of the schedule goes through.
#[derive(Clone, Copy, Debug)]
enum Path {
    Init,
    Uninit,
    /// Alternates, starting with the initialized slice.
    Mixed,
}

/// Mixed text, runs and noise, so every encoder takes both matches and literals.
fn payload(len: usize) -> Vec<u8> {
    let mut rng = Rng::new(0x0123_4567_89ab_cdef);
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

/// Reads bytes the test itself initialized or the encoder reported written.
fn read(bytes: &[MaybeUninit<u8>]) -> Vec<u8> {
    // SAFETY: callers pass only the reported prefix or sentinel-filled bytes,
    // all of which are initialized.
    bytes
        .iter()
        .map(|byte| unsafe { byte.assume_init() })
        .collect()
}

/// The largest input each quality is exercised with, keeping HQ affordable.
const fn input_len(quality: Quality) -> usize {
    if quality.get() >= 10 { 40_000 } else { 300_000 }
}

/// Streams `data` through one session and returns its bytes and every call's
/// progress.
fn stream(
    compressor: &mut Compressor,
    data: &[u8],
    chunk: usize,
    window: usize,
    path: Path,
) -> (Vec<u8>, Vec<Progress>) {
    let stream = StreamConfig::from(InputSize::Exact(data.len() as u64));
    let mut session = compressor.start(stream).expect("a legal stream");
    let mut initialized = vec![0u8; window];
    let mut uninitialized = vec![MaybeUninit::new(SENTINEL); window];
    let mut output = Vec::new();
    let mut calls = Vec::new();
    let mut offset = 0;
    for call in 0usize.. {
        let take = (data.len() - offset).min(chunk);
        let operation = if offset + take == data.len() {
            Operation::Finish
        } else {
            Operation::Process
        };
        let input = &data[offset..offset + take];
        let uninit = match path {
            Path::Init => false,
            Path::Uninit => true,
            Path::Mixed => call % 2 == 1,
        };
        let progress = if uninit {
            let progress = session
                .process_uninit(input, &mut uninitialized, operation)
                .expect("the session failed");
            output.extend(read(&uninitialized[..progress.produced]));
            assert!(
                read(&uninitialized[progress.produced..])
                    .iter()
                    .all(|&byte| byte == SENTINEL),
                "process_uninit wrote past `produced`"
            );
            uninitialized.fill(MaybeUninit::new(SENTINEL));
            progress
        } else {
            let progress = session
                .process(input, &mut initialized, operation)
                .expect("the session failed");
            output.extend_from_slice(&initialized[..progress.produced]);
            progress
        };
        offset += progress.consumed;
        calls.push(progress);
        if progress.status == EncoderStatus::Finished {
            break;
        }
    }
    assert!(session.is_finished());
    (output, calls)
}

#[test]
fn process_uninit_matches_process_for_every_quality_and_window() {
    for quality in IMPLEMENTED_QUALITIES {
        let data = payload(input_len(quality));
        for lgwin in [16, 22] {
            let mut compressor = encoder(quality, lgwin);
            for window in WINDOWS {
                for chunk in [1000, 1 << 16] {
                    let label = format!(
                        "q{} lgwin {lgwin} window {window} chunk {chunk}",
                        quality.get()
                    );
                    let expected = stream(&mut compressor, &data, chunk, window, Path::Init);
                    let uninit = stream(&mut compressor, &data, chunk, window, Path::Uninit);
                    assert_eq!(uninit, expected, "{label}: process_uninit");
                    let mixed = stream(&mut compressor, &data, chunk, window, Path::Mixed);
                    assert_eq!(mixed.0, expected.0, "{label}: mixed calls");
                    assert_eq!(
                        c_decompress(&expected.0, data.len()).as_deref(),
                        Some(data.as_slice()),
                        "{label}: the C decoder rejects the stream"
                    );
                }
            }
        }
    }
}

#[test]
fn process_uninit_finishes_an_empty_stream_and_stays_finished() {
    for quality in [Quality::Q0, Quality::Q1, Quality::Q5, Quality::Q11] {
        let mut compressor = encoder(quality, 22);
        let expected = compressor.compress(b"").expect("compresses");
        let mut session = compressor.start(StreamConfig::default()).expect("starts");
        let mut output = [MaybeUninit::new(SENTINEL); 8];
        let progress = session
            .process_uninit(b"", &mut output, Operation::Finish)
            .expect("finishes");
        assert_eq!(progress.status, EncoderStatus::Finished);
        assert_eq!(read(&output[..progress.produced]), expected);
        let again = session
            .process_uninit(b"", &mut [], Operation::Finish)
            .expect("stays finished");
        assert_eq!(
            again,
            Progress {
                consumed: 0,
                produced: 0,
                status: EncoderStatus::Finished,
            }
        );
    }
}

#[test]
fn process_uninit_on_an_empty_destination_reports_needs_output() {
    let mut compressor = encoder(Quality::Q1, 22);
    let mut session = compressor.start(StreamConfig::default()).expect("starts");
    let progress = session
        .process_uninit(b"payload", &mut [], Operation::Finish)
        .expect("keeps the output pending");
    assert_eq!(progress.status, EncoderStatus::NeedsOutput);
    assert_eq!(progress.produced, 0);
}

#[test]
fn owned_process_uninit_matches_the_borrowed_session() {
    let data = payload(100_000);
    for quality in [Quality::Q0, Quality::Q1, Quality::Q5] {
        let (expected, _) = stream(
            &mut encoder(quality, 16),
            &data,
            1 << 16,
            1 << 20,
            Path::Init,
        );
        let mut session = encoder(quality, 16)
            .into_session(InputSize::Exact(data.len() as u64).into())
            .expect("starts");
        let mut buffer = vec![MaybeUninit::uninit(); 1 << 20];
        let mut output = Vec::new();
        let mut input = data.as_slice();
        loop {
            let progress = session
                .process_uninit(input, &mut buffer, Operation::Finish)
                .expect("the session failed");
            input = &input[progress.consumed..];
            output.extend(read(&buffer[..progress.produced]));
            if progress.status == EncoderStatus::Finished {
                break;
            }
        }
        assert_eq!(output, expected, "q{}", quality.get());
        assert!(session.into_compressor().compress(b"reused").is_ok());
    }
}

#[test]
fn compress_to_uninit_matches_compress_to_slice() {
    for quality in IMPLEMENTED_QUALITIES {
        for len in [0, 1, 1000, input_len(quality)] {
            let data = payload(len);
            let mut compressor = encoder(quality, 22);
            let bound = Compressor::max_compressed_size(len).expect("bounded");
            let mut initialized = vec![0; bound];
            let written = compressor
                .compress_to_slice(&data, &mut initialized)
                .expect("compresses");
            let mut uninitialized = vec![MaybeUninit::new(SENTINEL); bound + 16];
            assert_eq!(
                compressor
                    .compress_to_uninit(&data, &mut uninitialized)
                    .ok(),
                Some(written),
                "q{} len {len}",
                quality.get()
            );
            assert_eq!(read(&uninitialized[..written]), &initialized[..written]);
            assert!(
                read(&uninitialized[written..])
                    .iter()
                    .all(|&byte| byte == SENTINEL),
                "q{} len {len}: wrote past the stream",
                quality.get()
            );
        }
    }
}

#[test]
fn compress_to_uninit_reports_a_short_destination_and_recovers() {
    for quality in [Quality::Q0, Quality::Q1, Quality::Q5] {
        let data = payload(10_000);
        let mut compressor = encoder(quality, 22);
        let mut short = vec![MaybeUninit::uninit(); 16];
        assert!(matches!(
            compressor.compress_to_uninit(&data, &mut short),
            Err(EncodeError::OutputTooSmall { provided: 16 })
        ));
        assert!(matches!(
            compressor.compress_to_uninit(b"", &mut []),
            Err(EncodeError::OutputTooSmall { provided: 0 })
        ));
        let mut room =
            vec![MaybeUninit::uninit(); Compressor::max_compressed_size(data.len()).unwrap()];
        let written = compressor
            .compress_to_uninit(&data, &mut room)
            .expect("the compressor recovered");
        assert_eq!(read(&room[..written]), compressor.compress(&data).unwrap());
    }
}
