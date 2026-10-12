#![cfg(feature = "compression")]
#![cfg(not(feature = "no_std"))]

//! Incremental parallel sessions: batch identity, windowing, flush, and failure.
mod support;
use mbrotli::compressor::parallel::*;
use mbrotli::{EncoderConfig, Operation, Quality};
use std::{error::Error, time::Duration};

const SEGMENT: usize = 64 << 10;

fn config(minimum: u64) -> ParallelConfig {
    ParallelConfig::from(SegmentSize::try_from(SEGMENT).unwrap())
        .with_minimum_parallel_size(minimum)
        .with_max_retained_workers(4)
}
fn compressor(q: u8, minimum: u64) -> ParallelCompressor {
    ParallelCompressor::new(
        EncoderConfig::default().with_quality(Quality::try_from(q).unwrap()),
        config(minimum),
    )
    .unwrap()
}
fn window(n: usize) -> TaskCount {
    TaskCount::try_from(n).unwrap()
}
/// Repeated text interleaved with low-alphabet noise, so every family finds
/// both matches and literals.
fn data(len: usize) -> Vec<u8> {
    let text = b"\xff\x00streaming the compression dictionary: encyclopedia \xc3\xa9 abcdefghij ";
    let mut rng = support::Rng::new(len as u64 + 7);
    let mut v = Vec::with_capacity(len + 512);
    while v.len() < len {
        v.extend_from_slice(text);
        v.extend(rng.bytes(200, 48));
    }
    v.truncate(len);
    v
}
fn batch(c: &mut ParallelCompressor, input: &[u8]) -> Vec<u8> {
    let mut b = c
        .prepare_slice(input, BatchConfig::auto(TaskCount::ONE))
        .unwrap();
    b.run_inline().unwrap();
    let mut out = Vec::new();
    b.finish_into(&mut out).unwrap();
    out
}

/// The calls both session shapes share, so one driver checks both.
trait Session {
    fn step(
        &mut self,
        input: &[u8],
        output: &mut [u8],
        operation: Operation,
    ) -> Result<ParallelProgress, ParallelEncodeError>;
    fn block(&mut self) -> Result<(), ParallelEncodeError>;
}
impl Session for ParallelEncoderSession<'_> {
    fn step(
        &mut self,
        input: &[u8],
        output: &mut [u8],
        operation: Operation,
    ) -> Result<ParallelProgress, ParallelEncodeError> {
        self.process(input, output, operation)
    }
    fn block(&mut self) -> Result<(), ParallelEncodeError> {
        self.wait()
    }
}
impl Session for ParallelEncoderSessionOwned {
    fn step(
        &mut self,
        input: &[u8],
        output: &mut [u8],
        operation: Operation,
    ) -> Result<ParallelProgress, ParallelEncodeError> {
        self.process(input, output, operation)
    }
    fn block(&mut self) -> Result<(), ParallelEncodeError> {
        self.wait()
    }
}

/// Feeds `input` in `chunk`-byte calls and collects output through an
/// `out`-byte buffer. With `inline`, queued tasks run on this thread.
fn drive(
    session: &mut impl Session,
    inline: Option<&ParallelTaskQueue>,
    input: &[u8],
    chunk: usize,
    out: usize,
) -> Vec<u8> {
    let mut output = Vec::new();
    let mut buffer = vec![0; out];
    let mut rest = input;
    loop {
        let take = rest.len().min(chunk);
        let operation = if take == rest.len() {
            Operation::Finish
        } else {
            Operation::Process
        };
        let progress = session.step(&rest[..take], &mut buffer, operation).unwrap();
        assert!(progress.consumed <= take && progress.produced <= out);
        rest = &rest[progress.consumed..];
        output.extend_from_slice(&buffer[..progress.produced]);
        match progress.status {
            ParallelEncoderStatus::Finished => return output,
            ParallelEncoderStatus::Pending => {
                if let Some(queue) = inline {
                    while let Some(task) = queue.try_recv() {
                        task.run();
                    }
                }
                session.block().unwrap();
            }
            ParallelEncoderStatus::NeedsInput | ParallelEncoderStatus::NeedsOutput => {}
        }
    }
}

/// Streams `input` through `threads` executors, or inline when zero.
fn streamed(
    c: &mut ParallelCompressor,
    input: &[u8],
    tasks: usize,
    chunk: usize,
    out: usize,
    threads: usize,
) -> Vec<u8> {
    std::thread::scope(|scope| {
        let (mut session, queue) = c.start(window(tasks)).unwrap();
        for _ in 0..threads {
            let queue = queue.clone();
            scope.spawn(move || queue.into_iter().for_each(|task| task.run()));
        }
        if threads == 0 {
            drive(&mut session, Some(&queue), input, chunk, out)
        } else {
            drop(queue);
            drive(&mut session, None, input, chunk, out)
        }
    })
}

#[test]
fn streams_match_the_batch_for_every_quality_chunking_window_and_executor() {
    let input = data(3 * SEGMENT + 1);
    for q in 0..=11 {
        let mut c = compressor(q, 0);
        let expected = batch(&mut c, &input);
        assert_eq!(
            support::c_decompress(&expected, input.len()).unwrap(),
            input,
            "q{q}"
        );
        for (tasks, chunk, out, threads) in [
            (1, usize::MAX, 1 << 20, 0),
            (2, 4097, 7, 2),
            (4, SEGMENT, SEGMENT, 4),
            (3, 1000, 1, 1),
        ] {
            assert_eq!(
                streamed(&mut c, &input, tasks, chunk, out, threads),
                expected,
                "q{q} window{tasks} chunk{chunk} out{out} threads{threads}"
            );
        }
    }
}

#[test]
fn serial_fallback_and_segment_edges_match_the_batch() {
    for q in [0, 1, 5, 9, 11] {
        for minimum in [0, 8 << 20] {
            let mut c = compressor(q, minimum);
            for n in [0, 1, 2, 3, SEGMENT - 1, SEGMENT, SEGMENT + 1, 2 * SEGMENT] {
                let input = data(n);
                let expected = batch(&mut c, &input);
                for chunk in [4096, usize::MAX] {
                    let out = streamed(&mut c, &input, 2, chunk, 1 << 20, 0);
                    assert_eq!(out, expected, "q{q} min{minimum} n{n} chunk{chunk}");
                }
                assert_eq!(support::c_decompress(&expected, n).unwrap(), input);
            }
        }
    }
}

#[test]
fn a_full_window_takes_no_more_input_and_reports_pending() {
    let input = data(3 * SEGMENT + 1);
    let mut c = compressor(1, 0);
    let expected = batch(&mut c, &input);
    let (mut session, queue) = c.start(TaskCount::ONE).unwrap();
    let mut output = vec![0; 1 << 20];
    let progress = session
        .process(&input, &mut output, Operation::Process)
        .unwrap();
    // One queued part plus one full filling segment.
    assert_eq!(progress.consumed, 2 * SEGMENT);
    assert_eq!(progress.produced, 0);
    assert_eq!(progress.status, ParallelEncoderStatus::Pending);
    assert_eq!(
        session.wait_timeout(Duration::ZERO).unwrap(),
        WaitStatus::TimedOut
    );
    let task = queue.try_recv().unwrap();
    assert!(queue.try_recv().is_none());
    let segments = task.segment_range();
    assert_eq!((u64::from(segments.start), u64::from(segments.end)), (0, 1));
    assert_eq!(u32::from(task.id()), 0);
    task.run();
    assert_eq!(
        session.wait_timeout(Duration::from_secs(60)).unwrap(),
        WaitStatus::Ready
    );
    let mut compressed = Vec::new();
    let mut rest = &input[progress.consumed..];
    loop {
        let progress = session
            .process(rest, &mut output, Operation::Finish)
            .unwrap();
        rest = &rest[progress.consumed..];
        compressed.extend_from_slice(&output[..progress.produced]);
        if progress.status == ParallelEncoderStatus::Finished {
            break;
        }
        while let Some(task) = queue.try_recv() {
            task.run();
        }
        session.wait().unwrap();
    }
    assert!(session.is_finished());
    assert_eq!(compressed, expected);
}

#[test]
fn flush_delivers_a_decodable_prefix_and_the_stream_still_round_trips() {
    let input = data(3 * SEGMENT);
    let split = SEGMENT + 1234;
    let mut c = compressor(5, 0);
    let mut compressed = Vec::new();
    std::thread::scope(|scope| {
        let (mut session, queue) = c.start(window(2)).unwrap();
        scope.spawn(move || queue.into_iter().for_each(|task| task.run()));
        let mut output = vec![0; 333];
        // Nothing accepted yet: a flush has nothing to deliver.
        let progress = session.flush(&mut output).unwrap();
        assert_eq!(progress.status, ParallelEncoderStatus::NeedsInput);
        assert_eq!(progress.produced, 0);
        let mut rest = &input[..split];
        loop {
            let progress = session
                .process(rest, &mut output, Operation::Flush)
                .unwrap();
            rest = &rest[progress.consumed..];
            compressed.extend_from_slice(&output[..progress.produced]);
            match progress.status {
                ParallelEncoderStatus::NeedsInput => break,
                ParallelEncoderStatus::Pending => session.wait().unwrap(),
                status => assert_eq!(status, ParallelEncoderStatus::NeedsOutput),
            }
        }
        assert!(rest.is_empty());
        assert_eq!(
            support::c_decompress_partial(&compressed, split).unwrap(),
            &input[..split]
        );
        let progress = session.flush(&mut output).unwrap();
        assert_eq!(progress.status, ParallelEncoderStatus::NeedsInput);
        assert_eq!(progress.produced, 0);
        compressed.extend(drive(&mut session, None, &input[split..], 5000, 333));
    });
    assert_eq!(
        support::c_decompress(&compressed, input.len()).unwrap(),
        input
    );
}

#[test]
fn finishing_ignores_input_and_a_finished_stream_stays_finished() {
    let mut c = compressor(3, 0);
    let expected = batch(&mut c, b"abc");
    let (mut session, queue) = c.start(TaskCount::ONE).unwrap();
    let mut output = [0u8; 64];
    let progress = session.process(b"abc", &mut [], Operation::Finish).unwrap();
    assert_eq!(progress.consumed, 3);
    assert_eq!(progress.status, ParallelEncoderStatus::Pending);
    let progress = session
        .process(b"more", &mut [], Operation::Process)
        .unwrap();
    assert_eq!(progress.consumed, 0);
    assert_eq!(progress.status, ParallelEncoderStatus::Pending);
    queue.recv().unwrap().run();
    session.wait().unwrap();
    // Encoded bytes wait for room.
    let progress = session.process(b"", &mut [], Operation::Finish).unwrap();
    assert_eq!(progress.status, ParallelEncoderStatus::NeedsOutput);
    let progress = session
        .process(b"ignored", &mut output, Operation::Flush)
        .unwrap();
    assert_eq!(progress.consumed, 0);
    assert_eq!(progress.status, ParallelEncoderStatus::Finished);
    assert_eq!(&output[..progress.produced], expected);
    assert!(session.is_finished());
    let again = session.finish(&mut output).unwrap();
    assert_eq!(
        again,
        ParallelProgress {
            consumed: 0,
            produced: 0,
            status: ParallelEncoderStatus::Finished,
        }
    );
    session.wait().unwrap();
    // Finishing closed the queue for executors.
    assert!(queue.recv().is_none());
}

#[test]
fn dropping_every_queue_handle_fails_the_stream_with_a_typed_cause() {
    let input = data(2 * SEGMENT);
    let mut c = compressor(0, 0);
    let (mut session, queue) = c.start(window(2)).unwrap();
    drop(queue);
    let error = session
        .process(&input, &mut [0; 64], Operation::Process)
        .unwrap_err();
    let ParallelEncodeError::StreamFailed(cause) = &error else {
        panic!("{error:?}");
    };
    assert!(matches!(**cause, ParallelEncodeError::TaskQueueClosed));
    assert_eq!(
        error.to_string(),
        "parallel stream failed: parallel task queue was closed by its executors"
    );
    assert!(matches!(
        error
            .source()
            .and_then(|e| e.downcast_ref::<std::sync::Arc<ParallelEncodeError>>())
            .map(|cause| &**cause),
        Some(ParallelEncodeError::TaskQueueClosed)
    ));
    // Every later call reports the same cause.
    for result in [
        session.finish(&mut [0; 64]).map(|_| ()),
        session.flush(&mut [0; 64]).map(|_| ()),
        session.wait(),
    ] {
        assert!(matches!(
            result,
            Err(ParallelEncodeError::StreamFailed(cause))
                if matches!(*cause, ParallelEncodeError::TaskQueueClosed)
        ));
    }
}

#[test]
fn a_dropped_task_or_queue_abandons_its_part_and_fails_the_stream() {
    let input = data(SEGMENT + 1);
    let mut c = compressor(0, 0);
    let (mut session, queue) = c.start(window(2)).unwrap();
    session
        .process(&input, &mut [0; 64], Operation::Process)
        .unwrap();
    drop(queue.try_recv().unwrap());
    assert!(matches!(
        session.wait(),
        Err(ParallelEncodeError::StreamFailed(cause))
            if matches!(*cause, ParallelEncodeError::TaskAbandoned { .. })
    ));
    drop(session);

    let (mut session, queue) = c.start(window(2)).unwrap();
    session
        .process(&input, &mut [0; 64], Operation::Finish)
        .unwrap();
    // The last handle abandons both queued parts instead of hanging `wait`.
    drop(queue);
    let error = loop {
        match session.wait() {
            Ok(()) => {}
            Err(error) => break error,
        }
    };
    assert!(matches!(
        error,
        ParallelEncodeError::StreamFailed(cause)
            if matches!(*cause, ParallelEncodeError::TaskAbandoned { .. })
    ));
}

#[test]
fn dropping_the_session_closes_the_queue_and_cancels_unstarted_tasks() {
    let input = data(2 * SEGMENT);
    let mut c = compressor(1, 0);
    let (mut session, queue) = c.start(window(4)).unwrap();
    session
        .process(&input, &mut [0; 64], Operation::Finish)
        .unwrap();
    let started = queue.try_recv().unwrap();
    let executor = {
        let queue = queue.clone();
        std::thread::spawn(move || queue.into_iter().count())
    };
    drop(session);
    // Unstarted tasks were abandoned with the queue; the executor's loop ends.
    executor.join().unwrap();
    assert!(queue.recv().is_none());
    // A task taken before the drop still runs and releases its own resources.
    started.run();
    let expected = batch(&mut compressor(1, 0), &input);
    assert_eq!(streamed(&mut c, &input, 2, usize::MAX, 4096, 2), expected);
}

#[test]
fn owned_sessions_match_borrowed_ones_and_return_a_reusable_compressor() {
    let input = data(2 * SEGMENT + 17);
    let mut c = compressor(6, 0);
    let expected = batch(&mut c, &input);
    let (mut session, queue) = c.into_session(window(3)).unwrap();
    let executors: Vec<_> = (0..2)
        .map(|_| {
            let queue = queue.clone();
            std::thread::spawn(move || queue.into_iter().for_each(|task| task.run()))
        })
        .collect();
    drop(queue);
    assert!(!session.is_finished());
    assert_eq!(drive(&mut session, None, &input, 3000, 100), expected);
    assert!(session.is_finished());
    let mut c = session.into_compressor();
    for executor in executors {
        executor.join().unwrap();
    }
    assert!(c.retained_worker_count() > 0);
    assert_eq!(streamed(&mut c, &input, 2, 4096, 4096, 0), expected);

    // Owned flush and finish shorthands, and an unfinished owned stream.
    let (mut session, queue) = c.into_session(TaskCount::ONE).unwrap();
    session
        .process(b"owned", &mut [], Operation::Process)
        .unwrap();
    assert_eq!(
        session.flush(&mut []).unwrap().status,
        ParallelEncoderStatus::Pending
    );
    queue.recv().unwrap().run();
    assert_eq!(
        session.wait_timeout(Duration::from_secs(60)).unwrap(),
        WaitStatus::Ready
    );
    let mut output = [0u8; 64];
    let flushed = session.flush(&mut output).unwrap();
    assert_eq!(flushed.status, ParallelEncoderStatus::NeedsInput);
    assert_eq!(
        session
            .finish(&mut output[flushed.produced..])
            .unwrap()
            .status,
        ParallelEncoderStatus::Finished
    );
    let executor = std::thread::spawn(move || queue.into_iter().count());
    let (session, queue) = session
        .into_compressor()
        .into_session(TaskCount::ONE)
        .unwrap();
    drop(session);
    assert!(queue.recv().is_none());
    assert_eq!(executor.join().unwrap(), 0);
}

#[test]
fn the_window_estimate_respects_the_aggregate_memory_limit() {
    let mut c = ParallelCompressor::new(
        EncoderConfig::default(),
        config(0).with_aggregate_memory_limit(Some(1)),
    )
    .unwrap();
    assert!(matches!(
        c.start(TaskCount::ONE),
        Err(ParallelEncodeError::WorkerMemoryLimit)
    ));
    c.reconfigure_parallel(config(0).with_aggregate_memory_limit(Some(usize::MAX)));
    assert!(c.start(window(4)).is_ok());
    #[cfg(target_pointer_width = "64")]
    {
        let c = ParallelCompressor::new(
            EncoderConfig::default().with_quality(Quality::Q11),
            ParallelConfig::from(SegmentSize::try_from(16 << 20).unwrap())
                .with_aggregate_memory_limit(Some(usize::MAX)),
        )
        .unwrap();
        assert!(matches!(
            c.into_session(window(u32::MAX as usize)),
            Err(ParallelEncodeError::SizeOverflow)
        ));
    }
}

#[test]
fn session_types_are_sendable_and_debuggable() {
    fn send_static<T: Send + 'static>() {}
    fn shared<T: Send + Sync + 'static>() {}
    send_static::<ParallelEncoderSessionOwned>();
    send_static::<ParallelTasks>();
    shared::<ParallelTaskQueue>();
    let mut c = compressor(0, 0);
    let (session, queue) = c.start(TaskCount::ONE).unwrap();
    assert!(format!("{session:?}").contains("finished: false"));
    assert!(format!("{queue:?}").contains("ParallelTaskQueue"));
    let mut tasks = queue.into_iter();
    assert!(format!("{tasks:?}").contains("ParallelTasks"));
    drop(session);
    assert!(tasks.next().is_none());
    let (session, _queue) = c.into_session(TaskCount::ONE).unwrap();
    assert!(format!("{session:?}").contains("ParallelEncoderSessionOwned"));
    assert_eq!(format!("{:?}", ParallelEncoderStatus::Pending), "Pending");
}
