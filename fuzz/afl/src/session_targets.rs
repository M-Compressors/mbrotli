//! Incremental session oracles for both codecs.
//!
//! Every session method is driven here, on borrowed and owned sessions alike:
//! `process` and `process_uninit` mixed call by call, the `flush` and `finish`
//! shorthands, idempotent calls after `Finished`, `reinit` from every state an
//! owned session can be in, and the codec an owned session hands back. The
//! other targets keep their one-shot and adapter oracles.

use std::mem::MaybeUninit;

use crate::decode_targets::{MAX_OUTPUT, config};
use crate::{Context, SENTINEL, assert_round_trip, cap, decode_case, read_output, sentinel_output};
use mbrotli::{
    DecodeError, DecodeFailure, DecodeOperation, DecodeProgress, DecodeStreamConfig,
    DecoderSession, DecoderSessionOwned, DecoderStatus, Decompressor, EncodeError, EncoderSession,
    EncoderSessionOwned, EncoderStatus, Operation, Progress,
};

/// The encoder session calls both session shapes answer.
trait EncodeStep {
    fn process(
        &mut self,
        input: &[u8],
        output: &mut [u8],
        operation: Operation,
    ) -> Result<Progress, EncodeError>;
    fn process_uninit(
        &mut self,
        input: &[u8],
        output: &mut [MaybeUninit<u8>],
        operation: Operation,
    ) -> Result<Progress, EncodeError>;
    fn flush(&mut self, output: &mut [u8]) -> Result<Progress, EncodeError>;
    fn finish(&mut self, output: &mut [u8]) -> Result<Progress, EncodeError>;
    fn is_finished(&self) -> bool;
}

macro_rules! encode_step {
    ($($session:ty),*) => {$(
        impl EncodeStep for $session {
            fn process(
                &mut self,
                input: &[u8],
                output: &mut [u8],
                operation: Operation,
            ) -> Result<Progress, EncodeError> {
                <$session>::process(self, input, output, operation)
            }
            fn process_uninit(
                &mut self,
                input: &[u8],
                output: &mut [MaybeUninit<u8>],
                operation: Operation,
            ) -> Result<Progress, EncodeError> {
                <$session>::process_uninit(self, input, output, operation)
            }
            fn flush(&mut self, output: &mut [u8]) -> Result<Progress, EncodeError> {
                <$session>::flush(self, output)
            }
            fn finish(&mut self, output: &mut [u8]) -> Result<Progress, EncodeError> {
                <$session>::finish(self, output)
            }
            fn is_finished(&self) -> bool {
                <$session>::is_finished(self)
            }
        }
    )*};
}

encode_step!(EncoderSession<'_, '_>, EncoderSessionOwned);

/// The decoder session calls both session shapes answer.
trait DecodeStep {
    fn process(
        &mut self,
        input: &[u8],
        output: &mut [u8],
        operation: DecodeOperation,
    ) -> Result<DecodeProgress, DecodeFailure>;
    fn process_uninit(
        &mut self,
        input: &[u8],
        output: &mut [MaybeUninit<u8>],
        operation: DecodeOperation,
    ) -> Result<DecodeProgress, DecodeFailure>;
    fn flush(&mut self, output: &mut [u8]) -> Result<DecodeProgress, DecodeFailure>;
    fn finish(&mut self, output: &mut [u8]) -> Result<DecodeProgress, DecodeFailure>;
    fn is_finished(&self) -> bool;
}

macro_rules! decode_step {
    ($($session:ty),*) => {$(
        impl DecodeStep for $session {
            fn process(
                &mut self,
                input: &[u8],
                output: &mut [u8],
                operation: DecodeOperation,
            ) -> Result<DecodeProgress, DecodeFailure> {
                <$session>::process(self, input, output, operation)
            }
            fn process_uninit(
                &mut self,
                input: &[u8],
                output: &mut [MaybeUninit<u8>],
                operation: DecodeOperation,
            ) -> Result<DecodeProgress, DecodeFailure> {
                <$session>::process_uninit(self, input, output, operation)
            }
            fn flush(&mut self, output: &mut [u8]) -> Result<DecodeProgress, DecodeFailure> {
                <$session>::flush(self, output)
            }
            fn finish(&mut self, output: &mut [u8]) -> Result<DecodeProgress, DecodeFailure> {
                <$session>::finish(self, output)
            }
            fn is_finished(&self) -> bool {
                <$session>::is_finished(self)
            }
        }
    )*};
}

decode_step!(DecoderSession<'_, '_>, DecoderSessionOwned);

/// Whether call `call` of a schedule goes through `process_uninit`.
const fn uninit_call(plan: u8, call: usize) -> bool {
    (plan >> (call % 8)) & 1 == 1
}

/// Asserts that `spare` holds [`SENTINEL`] past `produced`, appends the
/// produced bytes to `output` and refills `spare`.
fn take_uninit(spare: &mut [MaybeUninit<u8>], produced: usize, output: &mut Vec<u8>) {
    let bytes = read_output(spare);
    assert!(
        bytes[produced..].iter().all(|&byte| byte == SENTINEL),
        "process_uninit wrote past `produced`"
    );
    output.extend_from_slice(&bytes[..produced]);
    spare.fill(MaybeUninit::new(SENTINEL));
}

/// Encodes `data` through `session` in blocks of `chunk` bytes, into an
/// output window of `chunk` bytes, until it finishes.
///
/// Call `n` goes through `process_uninit` when bit `n % 8` of `plan` is set;
/// otherwise through `process`, or through the `finish` and `flush`
/// shorthands once a block's input has been taken. With `flush_every`, every
/// that-many-th block that is not the last is flushed.
fn drive_encoder(
    session: &mut impl EncodeStep,
    data: &[u8],
    chunk: usize,
    plan: u8,
    flush_every: Option<usize>,
) -> Vec<u8> {
    let mut buffer = vec![0u8; chunk];
    let mut spare = sentinel_output(chunk);
    let mut output = Vec::new();
    let mut offset = 0;
    let mut block_end = 0;
    let mut blocks = 0usize;
    let mut operation = Operation::Process;
    let mut repeat = false;
    for call in 0usize.. {
        if offset == block_end && !repeat {
            block_end = (offset + chunk).min(data.len());
            blocks += 1;
            operation = if block_end == data.len() {
                Operation::Finish
            } else if flush_every.is_some_and(|every| blocks % every == 0) {
                Operation::Flush
            } else {
                Operation::Process
            };
        }
        let input = &data[offset..block_end];
        let progress = if uninit_call(plan, call) {
            let progress = session
                .process_uninit(input, &mut spare, operation)
                .expect("the session failed");
            take_uninit(&mut spare, progress.produced, &mut output);
            progress
        } else {
            let progress = match operation {
                Operation::Finish if input.is_empty() => session.finish(&mut buffer),
                Operation::Flush if input.is_empty() => session.flush(&mut buffer),
                _ => session.process(input, &mut buffer, operation),
            }
            .expect("the session failed");
            output.extend_from_slice(&buffer[..progress.produced]);
            progress
        };
        assert!(
            progress.consumed <= input.len() && progress.produced <= chunk,
            "the session reported more than it was given"
        );
        offset += progress.consumed;
        repeat = progress.status == EncoderStatus::NeedsOutput;
        if progress.status == EncoderStatus::Finished {
            assert!(session.is_finished());
            assert_eq!(offset, data.len(), "finished before taking every byte");
            return output;
        }
        assert!(!session.is_finished(), "finished without reporting it");
    }
    unreachable!("the schedule is unbounded")
}

/// A finished encoder session consumes and produces nothing through either
/// method, and stays finished.
fn assert_encoder_stays_finished(session: &mut impl EncodeStep) {
    let finished = Progress {
        consumed: 0,
        produced: 0,
        status: EncoderStatus::Finished,
    };
    let mut buffer = [0u8; 16];
    assert_eq!(
        session
            .process(b"more", &mut buffer, Operation::Finish)
            .ok(),
        Some(finished)
    );
    let mut spare = sentinel_output(16);
    assert_eq!(
        session
            .process_uninit(b"more", &mut spare, Operation::Finish)
            .ok(),
        Some(finished)
    );
    assert!(read_output(&spare).iter().all(|&byte| byte == SENTINEL));
    assert_eq!(session.finish(&mut buffer).ok(), Some(finished));
    assert!(session.is_finished());
}

/// Encoder sessions of both shapes against the one-shot stream.
///
/// The last input byte is the plan: bit `n % 8` sends call `n` through
/// `process_uninit`, and its low two bits choose how often the flushing
/// schedule flushes. The rest is a [`decode_case`] input.
///
/// # Panics
///
/// Panics when a session's bytes differ from `compress`, the borrowed and
/// owned sessions disagree under the same flushing schedule, a flushed stream
/// does not round-trip, `process_uninit` writes past what it reports, a
/// finished session does anything, `reinit` misbehaves from any state, or the
/// returned compressor no longer matches a fresh one.
pub fn encoder_session(ctx: &Context, input: &[u8]) {
    let (plan, rest) = input
        .split_last()
        .map_or((0, input), |(&plan, rest)| (plan, rest));
    let case = decode_case(rest);
    let chunk = case.chunk.max(1);
    let expected = ctx
        .encoder(case.config)
        .compress(case.data)
        .expect("compression failed");

    let mut compressor = ctx.encoder(case.config);
    let mut owned = ctx
        .encoder(case.config)
        .into_session(case.stream)
        .expect("a legal stream");

    // Complementary mixes of the two methods reach the one-shot bytes.
    {
        let mut borrowed = compressor.start(case.stream).expect("a legal stream");
        let bytes = drive_encoder(&mut borrowed, case.data, chunk, plan, None);
        assert_eq!(bytes, expected, "the borrowed session disagrees");
        assert_encoder_stays_finished(&mut borrowed);
    }
    let bytes = drive_encoder(&mut owned, case.data, chunk, !plan, None);
    assert_eq!(bytes, expected, "the owned session disagrees");
    assert_encoder_stays_finished(&mut owned);

    // Flushes change the stream, identically for both shapes and methods.
    let every = Some(usize::from(plan & 3) + 1);
    let flushed = {
        let mut borrowed = compressor.start(case.stream).expect("a legal stream");
        drive_encoder(&mut borrowed, case.data, chunk, plan, every)
    };
    owned.reinit(case.stream).expect("reinit after Finished");
    let owned_flushed = drive_encoder(&mut owned, case.data, chunk, !plan, every);
    assert_eq!(flushed, owned_flushed, "flushed sessions disagree");
    assert_round_trip(case.data, &flushed);

    // Restart from every state an owned session can be in.
    let mut buffer = vec![0u8; chunk];
    let half = &case.data[..case.data.len() / 2];
    for state in 0..4 {
        match state {
            0 => {
                let _ = owned.process(half, &mut buffer, Operation::Process);
            }
            1 => {
                let _ = owned.process_uninit(half, &mut sentinel_output(chunk), Operation::Flush);
            }
            2 => match owned.reinit(case.stream.with_stream_offset(1)) {
                Ok(()) => {}
                Err(EncodeError::UnsupportedStreamOffset { .. }) => {
                    assert!(matches!(
                        owned.process(half, &mut buffer, Operation::Process),
                        Err(EncodeError::InvalidState { .. })
                    ));
                    assert!(matches!(
                        owned.process_uninit(half, &mut sentinel_output(chunk), Operation::Finish),
                        Err(EncodeError::InvalidState { .. })
                    ));
                }
                Err(error) => panic!("reinit failed unexpectedly: {error}"),
            },
            _ => {}
        }
        owned.reinit(case.stream).expect("reinit failed");
        let bytes = drive_encoder(&mut owned, case.data, chunk, plan.rotate_left(state), None);
        assert_eq!(bytes, expected, "a reinitialized session disagrees");
    }

    // Both compressors come back ready for the next operation.
    assert_eq!(
        owned
            .into_compressor()
            .compress(case.data)
            .expect("compression failed"),
        expected,
        "the owned session's compressor disagrees"
    );
    assert_eq!(
        compressor.compress(case.data).expect("compression failed"),
        expected,
        "the borrowed sessions' compressor disagrees"
    );
}

/// Where a decoder schedule ended.
#[derive(Debug, PartialEq, Eq)]
enum Ending {
    /// `Finished`, after taking `consumed` input bytes.
    Finished { consumed: usize },
    /// The session failed with this error.
    Failed(String),
}

/// Decodes `data` through `session`, fed in `chunk` byte pieces into an
/// output window of `window` bytes, until it finishes or fails.
///
/// Call `n` goes through `process_uninit` when bit `n % 8` of `plan` is set;
/// otherwise through `process`, `flush` to drain after `NeedsOutput`, or
/// `finish` once every input byte has been taken.
fn drive_decoder(
    session: &mut impl DecodeStep,
    data: &[u8],
    chunk: usize,
    window: usize,
    plan: u8,
) -> (Vec<u8>, Ending) {
    let mut buffer = vec![0u8; window];
    let mut spare = sentinel_output(window);
    let mut output = Vec::new();
    let mut cursor = 0;
    let mut draining = false;
    for call in 0..data.len() + MAX_OUTPUT + 2 {
        let end = (cursor + chunk).min(data.len());
        let operation = if end == data.len() {
            DecodeOperation::Finish
        } else {
            DecodeOperation::Process
        };
        let input = &data[cursor..end];
        let flushing = draining && operation == DecodeOperation::Process;
        let result = if uninit_call(plan, call) {
            let result = session.process_uninit(input, &mut spare, operation);
            let produced = match &result {
                Ok(progress) => progress.produced,
                Err(failure) => failure.produced,
            };
            take_uninit(&mut spare, produced, &mut output);
            result
        } else {
            let result = if input.is_empty() && operation == DecodeOperation::Finish {
                session.finish(&mut buffer)
            } else if flushing {
                session.flush(&mut buffer)
            } else {
                session.process(input, &mut buffer, operation)
            };
            let produced = match &result {
                Ok(progress) => progress.produced,
                Err(failure) => failure.produced,
            };
            output.extend_from_slice(&buffer[..produced]);
            result
        };
        let progress = match result {
            Ok(progress) => progress,
            Err(failure) => {
                assert!(failure.consumed <= input.len() && failure.produced <= window);
                return (output, Ending::Failed(format!("{:?}", failure.error)));
            }
        };
        assert!(progress.consumed <= input.len() && progress.produced <= window);
        assert!(output.len() <= MAX_OUTPUT);
        cursor += progress.consumed;
        if progress.status == DecoderStatus::Finished {
            assert!(session.is_finished());
            return (output, Ending::Finished { consumed: cursor });
        }
        assert!(
            flushing || progress.consumed != 0 || progress.produced != 0,
            "an active decoder made no progress"
        );
        draining = progress.status == DecoderStatus::NeedsOutput;
    }
    panic!("the decoder exceeded the progress bound");
}

/// Checks a schedule's ending against the one-shot outcome for the same bytes.
fn assert_decoder_matches(
    (output, ending): &(Vec<u8>, Ending),
    expected: &Result<Vec<u8>, DecodeError>,
    input_len: usize,
) {
    match (ending, expected) {
        (Ending::Finished { consumed }, Ok(expected)) => {
            assert_eq!(*consumed, input_len);
            assert_eq!(output, expected);
        }
        (Ending::Finished { consumed }, Err(DecodeError::TrailingData { offset })) => {
            assert_eq!(*consumed as u64, *offset);
        }
        (Ending::Finished { .. }, Err(error)) => {
            panic!("a session finished after one-shot failure: {error}")
        }
        (Ending::Failed(error), Ok(_)) => {
            panic!("a session rejected a stream one-shot accepts: {error}")
        }
        (Ending::Failed(_), Err(_)) => {}
    }
}

/// A finished decoder session consumes and produces nothing through either
/// method, and stays finished.
fn assert_decoder_stays_finished(session: &mut impl DecodeStep) {
    let finished = DecodeProgress {
        consumed: 0,
        produced: 0,
        status: DecoderStatus::Finished,
    };
    let mut buffer = [0u8; 16];
    assert_eq!(
        session
            .process(&[], &mut buffer, DecodeOperation::Finish)
            .ok(),
        Some(finished)
    );
    let mut spare = sentinel_output(16);
    assert_eq!(
        session
            .process_uninit(&[], &mut spare, DecodeOperation::Finish)
            .ok(),
        Some(finished)
    );
    assert!(read_output(&spare).iter().all(|&byte| byte == SENTINEL));
    assert!(session.is_finished());
}

/// Decoder sessions of both shapes against one-shot decoding of arbitrary
/// bytes.
///
/// The first byte chooses the input chunk, the last the output window, and
/// the second is the plan whose bit `n % 8` sends call `n` through
/// `process_uninit`.
///
/// # Panics
///
/// Panics when a session's outcome differs from `decompress`, the borrowed and
/// owned sessions disagree, `process_uninit` writes past what it reports, a
/// finished session does anything, `reinit` misbehaves from any state, or the
/// returned decoder no longer matches a fresh one.
pub fn decoder_session(ctx: &Context, data: &[u8]) {
    let data = cap(data);
    let build = || {
        Decompressor::builder(config())
            .with_backend(ctx.level)
            .build()
            .unwrap()
    };
    let expected = build().decompress(data);
    let chunk = data.first().map_or(1, |value| usize::from(value % 31) + 1);
    let window = data.last().map_or(1, |value| usize::from(value % 31) + 1);
    let plan = data.get(1).copied().unwrap_or(0);

    let mut decoder = build();
    let borrowed = {
        let mut session = decoder.start(DecodeStreamConfig::default()).unwrap();
        let outcome = drive_decoder(&mut session, data, chunk, window, plan);
        if matches!(outcome.1, Ending::Finished { .. }) {
            assert_decoder_stays_finished(&mut session);
        }
        outcome
    };
    assert_decoder_matches(&borrowed, &expected, data.len());

    let mut owned = build().into_session(DecodeStreamConfig::default()).unwrap();
    let outcome = drive_decoder(&mut owned, data, chunk, window, !plan);
    assert_eq!(outcome, borrowed, "the owned session disagrees");
    if matches!(outcome.1, Ending::Finished { .. }) {
        assert_decoder_stays_finished(&mut owned);
    }

    // Restart after finishing or failing, and from the middle of a stream.
    let half = &data[..data.len() / 2];
    for state in 0..3 {
        match state {
            1 => {
                let _ = owned.process(half, &mut [0; 3], DecodeOperation::Process);
            }
            2 => {
                let _ =
                    owned.process_uninit(half, &mut sentinel_output(3), DecodeOperation::Finish);
            }
            _ => {}
        }
        owned.reinit(DecodeStreamConfig::default()).unwrap();
        let outcome = drive_decoder(&mut owned, data, chunk, window, plan.rotate_left(state));
        assert_eq!(outcome, borrowed, "a reinitialized session disagrees");
    }

    // Both decoders come back ready for the next operation.
    let describe = |outcome: &Result<Vec<u8>, DecodeError>| format!("{outcome:?}");
    assert_eq!(
        describe(&owned.into_decompressor().decompress(data)),
        describe(&expected),
        "the owned session's decoder disagrees"
    );
    assert_eq!(
        describe(&decoder.decompress(data)),
        describe(&expected),
        "the borrowed sessions' decoder disagrees"
    );
}
