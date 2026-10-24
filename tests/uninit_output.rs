#![cfg(all(feature = "compression", feature = "decompression"))]
//! Uninitialized output that really starts uninitialized, sized for Miri.
//!
//! `encode_uninit` and `decode_uninit` compare the uninitialized APIs with
//! the initialized ones on large streams, in sentinel-filled buffers that
//! catch writes past the result. A sentinel-filled buffer is initialized,
//! though, so reading it back cannot show that a codec initialized what it
//! reported. Here every destination starts as `MaybeUninit::uninit()` and
//! only the reported prefix is read: under Miri, a count that covers a byte
//! the codec never wrote is undefined behavior and fails the test. Streams
//! come from this crate's encoder, which Miri can run, unlike the C one.

mod support;

use std::mem::MaybeUninit;

use mbrotli::{
    Compressor, DecodeError, DecodeOperation, DecodeStreamConfig, DecoderConfig, DecoderStatus,
    Decompressor, EncodeError, EncoderStatus, InputSize, MemberMode, Operation, Quality,
};
use support::{IMPLEMENTED_QUALITIES, Rng, encoder};

/// Output windows: single bytes, an odd size, and room for whole blocks.
const WINDOWS: [usize; 3] = [1, 13, 4096];

/// Text, runs and noise, so streams carry literals, copies and dictionary
/// references.
fn payload(len: usize) -> Vec<u8> {
    let mut rng = Rng::new(0x0123_4567_89ab_cdef);
    let mut data = Vec::with_capacity(len);
    while data.len() < len {
        match rng.next_u8() % 3 {
            0 => data.extend_from_slice(b"the quick brown fox jumps over the lazy dog. "),
            1 => data.extend(std::iter::repeat_n(rng.next_u8(), 41)),
            _ => data.extend(rng.bytes(29, 256)),
        }
    }
    data.truncate(len);
    data
}

/// A buffer of `len` bytes no one has written.
fn uninit(len: usize) -> Vec<MaybeUninit<u8>> {
    vec![MaybeUninit::uninit(); len]
}

/// Reads the prefix a codec reported writing.
fn read(bytes: &[MaybeUninit<u8>]) -> Vec<u8> {
    // SAFETY: callers pass only the prefix the codec reported initializing;
    // under Miri, a wrong report makes this read fail the test.
    bytes
        .iter()
        .map(|byte| unsafe { byte.assume_init() })
        .collect()
}

/// The qualities of `wanted` this run can execute.
///
/// Miri has no shim for two Neon intrinsics that qualities 10 and 11 reach
/// (see `CONTRIBUTING.md`), so under Miri on aarch64 those two are left to
/// AddressSanitizer.
fn runnable(wanted: &[Quality]) -> Vec<Quality> {
    let neon_gap = cfg!(all(miri, target_arch = "aarch64"));
    wanted
        .iter()
        .copied()
        .filter(|quality| !neon_gap || quality.get() < 10)
        .collect()
}

/// Compresses with this crate's encoder at a small window, which keeps the
/// high qualities' tables affordable under Miri.
fn compress(quality: Quality, data: &[u8]) -> Vec<u8> {
    encoder(quality, 16).compress(data).expect("compresses")
}

#[test]
fn compress_to_uninit_initializes_the_stream_it_reports_at_every_quality() {
    let data = payload(1500);
    for quality in runnable(&IMPLEMENTED_QUALITIES) {
        let mut compressor = encoder(quality, 16);
        let expected = compressor.compress(&data).expect("compresses");
        let mut output = uninit(Compressor::max_compressed_size(data.len()).expect("bounded"));
        let written = compressor
            .compress_to_uninit(&data, &mut output)
            .expect("compresses");
        assert_eq!(read(&output[..written]), expected, "q{}", quality.get());
    }
}

#[test]
fn compress_to_uninit_reports_a_short_destination_and_recovers() {
    let data = payload(1500);
    let mut compressor = encoder(Quality::Q1, 16);
    assert!(matches!(
        compressor.compress_to_uninit(&data, &mut uninit(8)),
        Err(EncodeError::OutputTooSmall { provided: 8 })
    ));
    let mut output = uninit(Compressor::max_compressed_size(data.len()).expect("bounded"));
    let written = compressor
        .compress_to_uninit(&data, &mut output)
        .expect("the compressor recovered");
    assert_eq!(read(&output[..written]), compress(Quality::Q1, &data));
}

#[test]
fn encoder_process_uninit_initializes_every_reported_prefix() {
    let data = payload(1500);
    for quality in runnable(&[Quality::Q0, Quality::Q1, Quality::Q5, Quality::Q11]) {
        let expected = compress(quality, &data);
        for window in WINDOWS {
            for chunk in [97, data.len()] {
                let mut compressor = encoder(quality, 16);
                let config = InputSize::Exact(data.len() as u64).into();
                let mut session = compressor.start(config).expect("a legal stream");
                let mut output = uninit(window);
                let mut stream = Vec::new();
                let mut offset = 0;
                loop {
                    let end = (offset + chunk).min(data.len());
                    let operation = if end == data.len() {
                        Operation::Finish
                    } else {
                        Operation::Process
                    };
                    let progress = session
                        .process_uninit(&data[offset..end], &mut output, operation)
                        .expect("the session failed");
                    offset += progress.consumed;
                    stream.extend(read(&output[..progress.produced]));
                    if progress.status == EncoderStatus::Finished {
                        break;
                    }
                }
                assert_eq!(
                    stream,
                    expected,
                    "q{} window {window} chunk {chunk}",
                    quality.get()
                );
            }
        }
    }
}

#[test]
fn owned_encoder_process_uninit_initializes_every_reported_prefix() {
    let data = payload(1500);
    for quality in [Quality::Q1, Quality::Q5] {
        let mut session = encoder(quality, 16)
            .into_session(InputSize::Exact(data.len() as u64).into())
            .expect("starts");
        let mut output = uninit(13);
        let mut stream = Vec::new();
        let mut input = data.as_slice();
        loop {
            let progress = session
                .process_uninit(input, &mut output, Operation::Finish)
                .expect("the session failed");
            input = &input[progress.consumed..];
            stream.extend(read(&output[..progress.produced]));
            if progress.status == EncoderStatus::Finished {
                break;
            }
        }
        assert_eq!(stream, compress(quality, &data), "q{}", quality.get());
    }
}

#[test]
fn decompress_to_uninit_initializes_what_it_decodes() {
    let mut decoder = Decompressor::new(Default::default()).expect("a decoder");
    // The last length spans three of the 32 KiB steps the destination is
    // zeroed in ahead of the decoder.
    for len in [0, 1, 1500, 70_000] {
        let data = payload(len);
        let qualities = if len > 10_000 {
            runnable(&[Quality::Q1])
        } else {
            runnable(&[Quality::Q0, Quality::Q5, Quality::Q11])
        };
        for quality in qualities {
            let compressed = compress(quality, &data);
            for capacity in [len, len + 100] {
                let mut output = uninit(capacity);
                let written = decoder
                    .decompress_to_uninit(&compressed, &mut output)
                    .expect("decodes");
                assert_eq!(written, len);
                assert_eq!(
                    read(&output[..written]),
                    data,
                    "q{} len {len}",
                    quality.get()
                );
            }
        }
    }
}

#[test]
fn decompress_to_uninit_initializes_the_prefix_a_short_destination_reports() {
    let mut decoder = Decompressor::new(Default::default()).expect("a decoder");
    let data = payload(1500);
    // An incompressible member is stored, which takes the copying path.
    let stored = Rng::new(0x5eed).bytes(1500, 256);
    for (quality, data) in [(Quality::Q5, &data), (Quality::Q9, &stored)] {
        let compressed = compress(quality, data);
        for capacity in [0, 1, 700, data.len() - 1] {
            let mut output = uninit(capacity);
            match decoder.decompress_to_uninit(&compressed, &mut output) {
                Err(DecodeError::OutputTooSmall { written }) => {
                    assert_eq!(read(&output[..written]), data[..written]);
                }
                other => panic!("capacity {capacity}: {other:?}"),
            }
        }
    }
}

#[test]
fn decompress_to_uninit_initializes_concatenated_members() {
    let config = DecoderConfig::default().with_member_mode(MemberMode::Concatenated);
    let mut decoder = Decompressor::new(config).expect("a decoder");
    let first = payload(1500);
    let second = b"the second member repeats itself. ".repeat(40);
    let mut compressed = compress(Quality::Q5, &first);
    compressed.extend(compress(Quality::Q1, &second));
    let total = first.len() + second.len();
    let mut output = uninit(total);
    assert_eq!(
        decoder.decompress_to_uninit(&compressed, &mut output).ok(),
        Some(total)
    );
    assert_eq!(read(&output), [first, second].concat());
}

#[test]
fn decompress_to_uninit_reports_truncated_input_without_claiming_output() {
    let mut decoder = Decompressor::new(Default::default()).expect("a decoder");
    let data = payload(1500);
    let compressed = compress(Quality::Q5, &data);
    let mut output = uninit(data.len());
    assert!(matches!(
        decoder.decompress_to_uninit(&compressed[..compressed.len() - 1], &mut output),
        Err(DecodeError::UnexpectedEndOfInput)
    ));
}

#[test]
fn decoder_process_uninit_initializes_every_reported_prefix() {
    let data = payload(1500);
    for quality in runnable(&[Quality::Q0, Quality::Q5, Quality::Q11]) {
        let compressed = compress(quality, &data);
        for window in WINDOWS {
            for chunk in [31, compressed.len()] {
                let mut decoder = Decompressor::new(Default::default()).expect("a decoder");
                let mut session = decoder
                    .start(DecodeStreamConfig::default())
                    .expect("starts");
                let mut output = uninit(window);
                let mut decoded = Vec::new();
                let mut offset = 0;
                loop {
                    let end = (offset + chunk).min(compressed.len());
                    let operation = if end == compressed.len() {
                        DecodeOperation::Finish
                    } else {
                        DecodeOperation::Process
                    };
                    let progress = session
                        .process_uninit(&compressed[offset..end], &mut output, operation)
                        .expect("decodes");
                    offset += progress.consumed;
                    decoded.extend(read(&output[..progress.produced]));
                    if progress.status == DecoderStatus::Finished {
                        break;
                    }
                }
                assert_eq!(
                    decoded,
                    data,
                    "q{} window {window} chunk {chunk}",
                    quality.get()
                );
            }
        }
    }
}

#[test]
fn decoder_process_uninit_initializes_the_progress_a_corrupt_stream_reports() {
    let data = payload(1500);
    let mut compressed = compress(Quality::Q5, &data);
    let middle = compressed.len() / 2;
    compressed[middle] ^= 0xff;
    compressed.truncate(middle + 16);
    let mut decoder = Decompressor::new(Default::default()).expect("a decoder");
    let mut initialized = vec![0; data.len()];
    let expected = decoder
        .start(DecodeStreamConfig::default())
        .expect("starts")
        .process(&compressed, &mut initialized, DecodeOperation::Finish)
        .expect_err("the stream is corrupt");
    let mut output = uninit(data.len());
    let failure = decoder
        .start(DecodeStreamConfig::default())
        .expect("starts")
        .process_uninit(&compressed, &mut output, DecodeOperation::Finish)
        .expect_err("the stream is corrupt");
    assert_eq!(failure.produced, expected.produced);
    assert_eq!(
        read(&output[..failure.produced]),
        initialized[..expected.produced]
    );
}

#[test]
fn owned_decoder_process_uninit_initializes_every_reported_prefix() {
    let data = payload(1500);
    let compressed = compress(Quality::Q9, &data);
    let mut session = Decompressor::new(Default::default())
        .expect("a decoder")
        .into_session(DecodeStreamConfig::default())
        .expect("starts");
    let mut output = uninit(127);
    let mut decoded = Vec::new();
    let mut input = compressed.as_slice();
    loop {
        let progress = session
            .process_uninit(input, &mut output, DecodeOperation::Finish)
            .expect("decodes");
        input = &input[progress.consumed..];
        decoded.extend(read(&output[..progress.produced]));
        if progress.status == DecoderStatus::Finished {
            break;
        }
    }
    assert_eq!(decoded, data);
}
