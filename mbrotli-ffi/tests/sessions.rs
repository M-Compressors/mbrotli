//! C session lifecycle and uninitialized destinations, without a native C oracle
//! so these tests can also run under Miri.
use mbrotli_ffi::*;
use std::mem::MaybeUninit;
use std::ptr::{null, null_mut};

fn append(output: &mut Vec<u8>, buffer: &[MaybeUninit<u8>], written: usize) {
    assert!(written <= buffer.len());
    output.extend(buffer[..written].iter().map(|byte| {
        // SAFETY: the session reported this byte initialized, including on decode failure.
        unsafe { byte.assume_init() }
    }));
}

#[test]
fn chunked_uninit_round_trip_flush_finish_and_reinit() {
    // SAFETY: handles are created here, used exclusively and destroyed once;
    // all pointers refer to disjoint live storage with the specified lengths.
    unsafe {
        let encoder = mbrotli_encoder_session_create(0, 22);
        let decoder = mbrotli_decoder_session_create();
        assert!(!encoder.is_null() && !decoder.is_null());
        for payload in [&b""[..], &b"hello hello hello"[..]] {
            let mut wire = Vec::new();
            for chunk in payload.chunks(3) {
                let mut remaining = chunk;
                while !remaining.is_empty() {
                    let mut output = [MaybeUninit::uninit(); 2];
                    let (mut read, mut written) = (remaining.len(), output.len());
                    let status = mbrotli_encoder_session_process(
                        encoder,
                        remaining.as_ptr(),
                        &mut read,
                        output.as_mut_ptr().cast(),
                        &mut written,
                        0,
                    );
                    assert!(matches!(
                        status,
                        MbrotliResult::NeedsInput | MbrotliResult::NeedsOutput
                    ));
                    remaining = &remaining[read..];
                    append(&mut wire, &output, written);
                }
                loop {
                    let mut output = [MaybeUninit::uninit(); 2];
                    let mut written = output.len();
                    let status = mbrotli_encoder_session_flush(
                        encoder,
                        output.as_mut_ptr().cast(),
                        &mut written,
                    );
                    append(&mut wire, &output, written);
                    if status == MbrotliResult::NeedsInput {
                        break;
                    }
                    assert_eq!(status, MbrotliResult::NeedsOutput);
                }
            }
            loop {
                let mut output = [MaybeUninit::uninit(); 2];
                let mut written = output.len();
                let status = mbrotli_encoder_session_finish(
                    encoder,
                    output.as_mut_ptr().cast(),
                    &mut written,
                );
                append(&mut wire, &output, written);
                if status == MbrotliResult::Finished {
                    break;
                }
                assert_eq!(status, MbrotliResult::NeedsOutput);
            }
            let mut restored = Vec::new();
            for chunk in wire.chunks(1) {
                let mut remaining = chunk;
                loop {
                    let mut output = [MaybeUninit::uninit(); 1];
                    let (mut read, mut written) = (remaining.len(), output.len());
                    let status = mbrotli_decoder_session_process(
                        decoder,
                        remaining.as_ptr(),
                        &mut read,
                        output.as_mut_ptr().cast(),
                        &mut written,
                        0,
                    );
                    remaining = &remaining[read..];
                    append(&mut restored, &output, written);
                    if status != MbrotliResult::NeedsOutput {
                        assert!(matches!(
                            status,
                            MbrotliResult::NeedsInput | MbrotliResult::Finished
                        ));
                        assert!(remaining.is_empty());
                        break;
                    }
                }
            }
            let mut output = [MaybeUninit::uninit(); 2];
            let mut written = output.len();
            assert_eq!(
                mbrotli_decoder_session_finish(decoder, output.as_mut_ptr().cast(), &mut written),
                MbrotliResult::Finished
            );
            append(&mut restored, &output, written);
            assert_eq!(restored, payload);
            assert_eq!(mbrotli_encoder_session_reinit(encoder), MbrotliResult::Ok);
            assert_eq!(mbrotli_decoder_session_reinit(decoder), MbrotliResult::Ok);
            written = output.len();
            assert_eq!(
                mbrotli_decoder_session_flush(decoder, output.as_mut_ptr().cast(), &mut written),
                MbrotliResult::NeedsInput
            );
            assert_eq!(written, 0);
        }
        mbrotli_encoder_session_destroy(encoder);
        mbrotli_decoder_session_destroy(decoder);
        mbrotli_encoder_session_destroy(null_mut());
        mbrotli_decoder_session_destroy(null_mut());
    }
}

#[test]
fn finish_backpressure_preserves_counts_and_trailing_input() {
    // SAFETY: exclusive live handles and disjoint buffers/counts; only initialized
    // output prefixes are read and each handle is destroyed exactly once.
    unsafe {
        let encoder = mbrotli_encoder_session_create(0, 22);
        let mut read = 3;
        let mut written = 0;
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                b"abc".as_ptr(),
                &mut read,
                null_mut(),
                &mut written,
                2
            ),
            MbrotliResult::NeedsOutput
        );
        assert_eq!(read, 3);
        let mut output = [MaybeUninit::uninit(); 32];
        written = output.len();
        assert_eq!(
            mbrotli_encoder_session_finish(encoder, output.as_mut_ptr().cast(), &mut written),
            MbrotliResult::Finished
        );
        let mut wire = Vec::new();
        append(&mut wire, &output, written);
        wire.extend_from_slice(b"trailing");
        let decoder = mbrotli_decoder_session_create();
        read = wire.len();
        written = 0;
        assert_eq!(
            mbrotli_decoder_session_process(
                decoder,
                wire.as_ptr(),
                &mut read,
                null_mut(),
                &mut written,
                2
            ),
            MbrotliResult::NeedsOutput
        );
        let remaining = &wire[read..];
        read = remaining.len();
        written = output.len();
        assert_eq!(
            mbrotli_decoder_session_process(
                decoder,
                remaining.as_ptr(),
                &mut read,
                output.as_mut_ptr().cast(),
                &mut written,
                2
            ),
            MbrotliResult::Finished
        );
        let mut restored = Vec::new();
        append(&mut restored, &output, written);
        assert_eq!(restored, b"abc");
        assert_eq!(&remaining[read..], b"trailing");
        mbrotli_encoder_session_destroy(encoder);
        mbrotli_decoder_session_destroy(decoder);
    }
}

#[test]
fn decoder_failure_preserves_initialized_prefix_and_reinit_recovers() {
    // A stored member missing its last header yields its payload before EOF fails.
    let wire = [0x0b, 0x02, 0x80, b'h', b'e', b'l', b'l', b'o'];
    // SAFETY: exclusive handle and valid disjoint storage throughout its lifetime.
    unsafe {
        let decoder = mbrotli_decoder_session_create();
        let mut output = [MaybeUninit::uninit(); 16];
        let (mut read, mut written) = (wire.len(), output.len());
        assert_eq!(
            mbrotli_decoder_session_process(
                decoder,
                wire.as_ptr(),
                &mut read,
                output.as_mut_ptr().cast(),
                &mut written,
                2
            ),
            MbrotliResult::Error
        );
        assert_eq!(read, wire.len());
        let mut restored = Vec::new();
        append(&mut restored, &output, written);
        assert_eq!(restored, b"hello");
        written = output.len();
        assert_eq!(
            mbrotli_decoder_session_flush(decoder, output.as_mut_ptr().cast(), &mut written),
            MbrotliResult::Error
        );
        assert_eq!(written, 0);
        assert_eq!(mbrotli_decoder_session_reinit(decoder), MbrotliResult::Ok);
        read = 1;
        written = output.len();
        assert_eq!(
            mbrotli_decoder_session_process(
                decoder,
                [6].as_ptr(),
                &mut read,
                output.as_mut_ptr().cast(),
                &mut written,
                2
            ),
            MbrotliResult::Finished
        );
        mbrotli_decoder_session_destroy(decoder);
    }
}

#[test]
fn invalid_arguments_leave_counts_and_sessions_unchanged() {
    assert!(mbrotli_encoder_session_create(-1, 22).is_null());
    assert!(mbrotli_encoder_session_create(5, 25).is_null());
    // SAFETY: deliberately invalid null/overlapping/misaligned arguments are
    // rejected before reference construction. All dereferenced storage is live.
    unsafe {
        let encoder = mbrotli_encoder_session_create(0, 22);
        let decoder = mbrotli_decoder_session_create();
        let (mut read, mut written) = (0, 0);
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                null(),
                &mut read,
                null_mut(),
                &mut written,
                99
            ),
            MbrotliResult::InvalidParameter
        );
        assert_eq!(
            mbrotli_decoder_session_process(
                decoder,
                null(),
                &mut read,
                null_mut(),
                &mut written,
                1
            ),
            MbrotliResult::InvalidParameter
        );
        assert_eq!(
            mbrotli_encoder_session_process(encoder, null(), &mut read, null_mut(), &mut read, 0),
            MbrotliResult::InvalidParameter
        );
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                null(),
                null_mut(),
                null_mut(),
                &mut written,
                0
            ),
            MbrotliResult::InvalidParameter
        );
        read = 1;
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                null(),
                &mut read,
                null_mut(),
                &mut written,
                0
            ),
            MbrotliResult::InvalidParameter
        );
        assert_eq!((read, written), (1, 0));
        let mut bytes = [0u8; 16];
        written = 1;
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                bytes.as_ptr(),
                &mut read,
                bytes.as_mut_ptr(),
                &mut written,
                0
            ),
            MbrotliResult::InvalidParameter
        );
        written = size_of::<usize>();
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                bytes.as_ptr(),
                &mut read,
                (&raw mut read).cast(),
                &mut written,
                0
            ),
            MbrotliResult::InvalidParameter
        );
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                bytes.as_ptr(),
                &mut read,
                bytes.as_mut_ptr(),
                bytes.as_mut_ptr().add(1).cast(),
                0
            ),
            MbrotliResult::InvalidParameter
        );
        assert_eq!(
            mbrotli_encoder_session_reinit(null_mut()),
            MbrotliResult::InvalidParameter
        );
        assert_eq!(
            mbrotli_decoder_session_reinit(null_mut()),
            MbrotliResult::InvalidParameter
        );
        assert_eq!(
            mbrotli_decoder_session_process(
                null_mut(),
                null(),
                &mut read,
                null_mut(),
                &mut written,
                0
            ),
            MbrotliResult::InvalidParameter
        );
        // Use the valid handle's address for overlap validation without accessing
        // its private allocation; count overlap is rejected before reading it.
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                null(),
                encoder.cast(),
                null_mut(),
                &mut written,
                0
            ),
            MbrotliResult::InvalidParameter
        );
        let misaligned = encoder.cast::<u8>().wrapping_add(1).cast();
        assert_eq!(
            mbrotli_encoder_session_reinit(misaligned),
            MbrotliResult::InvalidParameter
        );
        mbrotli_encoder_session_destroy(misaligned);
        read = 1;
        written = 0;
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                encoder.cast(),
                &mut read,
                null_mut(),
                &mut written,
                0
            ),
            MbrotliResult::InvalidParameter
        );
        read = 0;
        written = 1;
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                null(),
                &mut read,
                encoder.cast(),
                &mut written,
                0
            ),
            MbrotliResult::InvalidParameter
        );
        read = usize::MAX;
        written = 0;
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                bytes.as_ptr(),
                &mut read,
                null_mut(),
                &mut written,
                0
            ),
            MbrotliResult::InvalidParameter
        );
        assert_eq!(read, usize::MAX);
        read = 0;
        written = 0;
        assert_eq!(
            mbrotli_encoder_session_process(
                encoder,
                null(),
                &mut read,
                null_mut(),
                &mut written,
                0
            ),
            MbrotliResult::NeedsInput
        );
        mbrotli_encoder_session_destroy(encoder);
        mbrotli_decoder_session_destroy(decoder);
    }
}
