#![cfg(feature = "compression")]
#![cfg(not(feature = "no_std"))]

//! `std::io` adapters over parallel sessions: batch identity, flush, faults.
mod support;
use mbrotli::EncoderConfig;
use mbrotli::Quality;
use mbrotli::compressor::parallel::*;
use mbrotli::io::FinishError;
use std::io::{Error, ErrorKind, Read, Result, Write};

const SEGMENT: usize = 64 << 10;

fn compressor_with(q: u8, minimum: u64, segment: usize) -> ParallelCompressor {
    ParallelCompressor::new(
        EncoderConfig::default().with_quality(Quality::try_from(q).unwrap()),
        ParallelConfig::from(SegmentSize::try_from(segment).unwrap())
            .with_minimum_parallel_size(minimum)
            .with_max_retained_workers(4),
    )
    .unwrap()
}
fn compressor(q: u8, minimum: u64) -> ParallelCompressor {
    compressor_with(q, minimum, SEGMENT)
}
fn window(n: usize) -> TaskCount {
    TaskCount::try_from(n).unwrap()
}
/// Repeated text interleaved with low-alphabet noise.
fn data(len: usize) -> Vec<u8> {
    let text = b"\xff\x00parallel adapters over the compression dictionary \xc3\xa9 0123456789 ";
    let mut rng = support::Rng::new(len as u64 + 11);
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
/// The typed parallel error inside an adapter's I/O error.
fn parallel_cause(error: &Error) -> &ParallelEncodeError {
    error
        .get_ref()
        .and_then(|e| e.downcast_ref::<ParallelEncodeError>())
        .unwrap_or_else(|| panic!("not a parallel error: {error:?}"))
}

/// Writes `input` in `chunk`-byte writes through `threads` executors.
fn written(
    c: &mut ParallelCompressor,
    input: &[u8],
    tasks: usize,
    chunk: usize,
    threads: usize,
) -> Vec<u8> {
    std::thread::scope(|scope| {
        let (mut sink, queue) = c.writer(Vec::new(), window(tasks)).unwrap();
        for _ in 0..threads {
            let queue = queue.clone();
            scope.spawn(move || queue.into_iter().for_each(|task| task.run()));
        }
        drop(queue);
        for piece in input.chunks(chunk) {
            sink.write_all(piece).unwrap();
        }
        sink.finish().map_err(FinishError::into_error).unwrap()
    })
}

/// A source that hands out at most `step` bytes per read.
struct Trickle<'a> {
    data: &'a [u8],
    step: usize,
}
impl Read for Trickle<'_> {
    fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        let n = buf.len().min(self.step).min(self.data.len());
        buf[..n].copy_from_slice(&self.data[..n]);
        self.data = &self.data[n..];
        Ok(n)
    }
}

/// Reads the compressed form of `input` into `out`-byte buffers.
fn read(
    c: &mut ParallelCompressor,
    input: &[u8],
    tasks: usize,
    step: usize,
    out: usize,
    threads: usize,
) -> Vec<u8> {
    std::thread::scope(|scope| {
        let source = Trickle { data: input, step };
        let (mut source, queue) = c.reader(source, window(tasks)).unwrap();
        for _ in 0..threads {
            let queue = queue.clone();
            scope.spawn(move || queue.into_iter().for_each(|task| task.run()));
        }
        drop(queue);
        let mut compressed = Vec::new();
        let mut buffer = vec![0; out];
        loop {
            let n = source.read(&mut buffer).unwrap();
            if n == 0 {
                break;
            }
            compressed.extend_from_slice(&buffer[..n]);
        }
        assert!(source.is_finished());
        compressed
    })
}

#[test]
fn writers_match_the_batch_for_every_quality_write_size_and_window() {
    let input = data(3 * SEGMENT + 1);
    for q in 0..=11 {
        let mut c = compressor(q, 0);
        let expected = batch(&mut c, &input);
        for (tasks, chunk, threads) in [(1, usize::MAX, 1), (2, 4097, 2), (4, 1000, 4), (3, 7, 1)] {
            assert_eq!(
                written(&mut c, &input, tasks, chunk, threads),
                expected,
                "q{q} window{tasks} chunk{chunk} threads{threads}"
            );
        }
    }
}

#[test]
fn readers_match_the_batch_for_every_quality_source_split_and_buffer() {
    let input = data(3 * SEGMENT + 1);
    for q in 0..=11 {
        let mut c = compressor(q, 0);
        let expected = batch(&mut c, &input);
        for (tasks, step, out, threads) in [
            (1, usize::MAX, 1 << 20, 1),
            (2, 4097, 7, 2),
            (4, SEGMENT, SEGMENT, 4),
            (3, 1000, 1, 1),
        ] {
            assert_eq!(
                read(&mut c, &input, tasks, step, out, threads),
                expected,
                "q{q} window{tasks} step{step} out{out} threads{threads}"
            );
        }
    }
}

#[test]
fn adapters_reproduce_the_serial_fallback_and_segment_edges() {
    for q in [0, 1, 5, 9, 11] {
        for minimum in [0, 8 << 20] {
            let mut c = compressor(q, minimum);
            for n in [0, 1, 2, SEGMENT - 1, SEGMENT, SEGMENT + 1, 2 * SEGMENT] {
                let input = data(n);
                let expected = batch(&mut c, &input);
                assert_eq!(written(&mut c, &input, 2, 4096, 1), expected, "q{q} n{n}");
                assert_eq!(
                    read(&mut c, &input, 2, 4096, 4096, 1),
                    expected,
                    "q{q} n{n}"
                );
                assert_eq!(support::c_decompress(&expected, n).unwrap(), input);
            }
        }
    }
}

#[test]
fn parts_larger_than_one_pull_are_delivered_in_several() {
    // Incompressible 256 KiB segments compress to more than the 128 KiB the
    // writer pulls at once.
    let segment = 256 << 10;
    let input = support::Rng::new(3).bytes(2 * segment + 5, 256);
    let mut c = compressor_with(1, 0, segment);
    let expected = batch(&mut c, &input);
    assert!(expected.len() > input.len());
    assert_eq!(written(&mut c, &input, 1, usize::MAX, 1), expected);
    assert_eq!(read(&mut c, &input, 1, usize::MAX, 1 << 20, 1), expected);
}

#[test]
fn flush_makes_the_prefix_decodable_and_the_stream_still_round_trips() {
    let input = data(2 * SEGMENT + 300);
    let split = SEGMENT + 100;
    let mut c = compressor(5, 0);
    let compressed = std::thread::scope(|scope| {
        let (mut sink, queue) = c.writer(Vec::new(), window(2)).unwrap();
        scope.spawn(move || queue.into_iter().for_each(|task| task.run()));
        sink.write_all(&input[..split]).unwrap();
        sink.flush().unwrap();
        let flushed = sink.get_ref().len();
        assert_eq!(
            support::c_decompress_partial(sink.get_ref(), split).unwrap(),
            &input[..split]
        );
        // Nothing written since: a second flush emits nothing.
        sink.flush().unwrap();
        assert_eq!(sink.get_ref().len(), flushed);
        sink.write_all(&input[split..]).unwrap();
        sink.finish().map_err(FinishError::into_error).unwrap()
    });
    assert_eq!(
        support::c_decompress(&compressed, input.len()).unwrap(),
        input
    );
}

/// A sink that accepts at most `accept` bytes per write and, every
/// `fail_every` calls, fails with `kind` instead.
struct FaultySink {
    written: Vec<u8>,
    accept: usize,
    fail_every: usize,
    calls: usize,
    kind: ErrorKind,
}
impl FaultySink {
    fn new(accept: usize, fail_every: usize, kind: ErrorKind) -> Self {
        Self {
            written: Vec::new(),
            accept,
            fail_every,
            calls: 0,
            kind,
        }
    }
}
impl Write for FaultySink {
    fn write(&mut self, buf: &[u8]) -> Result<usize> {
        self.calls += 1;
        if self.calls.is_multiple_of(self.fail_every) {
            return Err(Error::new(self.kind, "injected"));
        }
        let n = buf.len().min(self.accept);
        self.written.extend_from_slice(&buf[..n]);
        Ok(n)
    }
    fn flush(&mut self) -> Result<()> {
        self.calls += 1;
        if self.calls.is_multiple_of(self.fail_every) {
            return Err(Error::new(self.kind, "injected"));
        }
        Ok(())
    }
}

#[test]
fn a_failing_sink_loses_nothing_and_finishing_can_be_retried() {
    let input = data(3 * SEGMENT + 17);
    let mut c = compressor(1, 0);
    let expected = batch(&mut c, &input);
    for kind in [
        ErrorKind::WouldBlock,
        ErrorKind::Interrupted,
        ErrorKind::Other,
    ] {
        let out = std::thread::scope(|scope| {
            let sink = FaultySink::new(1000, 5, kind);
            let (mut sink, queue) = c.writer(sink, window(2)).unwrap();
            scope.spawn(move || queue.into_iter().for_each(|task| task.run()));
            let mut rest = input.as_slice();
            while !rest.is_empty() {
                match sink.write(&rest[..rest.len().min(5000)]) {
                    Ok(n) => rest = &rest[n..],
                    Err(error) => assert_eq!(error.kind(), kind),
                }
            }
            loop {
                match sink.finish() {
                    Ok(inner) => break inner.written,
                    Err(failure) => {
                        assert_eq!(failure.error().kind(), kind);
                        sink = failure.into_inner();
                    }
                }
            }
        });
        assert_eq!(out, expected, "{kind:?}");
    }
}

#[test]
fn a_sink_that_accepts_nothing_is_reported_as_write_zero() {
    let mut c = compressor(0, 0);
    let (mut sink, _queue) = c
        .writer(
            FaultySink::new(0, usize::MAX, ErrorKind::Other),
            TaskCount::ONE,
        )
        .unwrap();
    // An empty stream is encoded inline, so finishing needs no executor.
    let error = sink.try_finish().unwrap_err();
    assert_eq!(error.kind(), ErrorKind::WriteZero);
    assert!(!sink.is_finished());
}

#[test]
fn writing_after_finishing_is_refused_but_flushing_reaches_the_sink() {
    let mut c = compressor(0, 0);
    let (mut sink, _queue) = c.writer(Vec::new(), TaskCount::ONE).unwrap();
    assert_eq!(sink.write(&[]).unwrap(), 0);
    sink.try_finish().unwrap();
    sink.try_finish().unwrap();
    assert!(sink.is_finished());
    assert_eq!(
        sink.write(b"late").unwrap_err().kind(),
        ErrorKind::InvalidInput
    );
    sink.flush().unwrap();
    assert_eq!(sink.get_ref().as_slice(), batch(&mut compressor(0, 0), &[]));
}

#[test]
fn dropping_every_queue_handle_fails_writes_and_reads_with_the_typed_cause() {
    let input = data(2 * SEGMENT + 1);
    let mut c = compressor(0, 0);
    let (mut sink, queue) = c.writer(Vec::new(), window(2)).unwrap();
    drop(queue);
    let error = sink.write_all(&input).unwrap_err();
    assert_eq!(error.kind(), ErrorKind::Other);
    let ParallelEncodeError::StreamFailed(cause) = parallel_cause(&error) else {
        panic!("{error:?}");
    };
    assert!(matches!(**cause, ParallelEncodeError::TaskQueueClosed));
    // The failure is sticky, including for finishing.
    let error = sink.finish().unwrap_err();
    assert!(matches!(
        parallel_cause(error.error()),
        ParallelEncodeError::StreamFailed(_)
    ));
    let mut sink = error.into_inner();
    assert!(matches!(
        parallel_cause(&sink.flush().unwrap_err()),
        ParallelEncodeError::StreamFailed(_)
    ));
    drop(sink);

    let (mut source, queue) = c.reader(input.as_slice(), window(2)).unwrap();
    drop(queue);
    let error = source.read_to_end(&mut Vec::new()).unwrap_err();
    let ParallelEncodeError::StreamFailed(cause) = parallel_cause(&error) else {
        panic!("{error:?}");
    };
    assert!(matches!(**cause, ParallelEncodeError::TaskQueueClosed));
}

/// A source that is interrupted, then fails once, before every chunk.
struct Stuttering<'a> {
    data: &'a [u8],
    calls: usize,
}
impl Read for Stuttering<'_> {
    fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        self.calls += 1;
        match self.calls % 3 {
            1 => Err(Error::new(ErrorKind::Interrupted, "again")),
            2 => Err(Error::other("injected")),
            _ => {
                let n = buf.len().min(10_000).min(self.data.len());
                buf[..n].copy_from_slice(&self.data[..n]);
                self.data = &self.data[n..];
                Ok(n)
            }
        }
    }
}

#[test]
fn readers_retry_interruptions_and_resume_after_source_errors() {
    let input = data(2 * SEGMENT + 9);
    let mut c = compressor(1, 0);
    let expected = batch(&mut c, &input);
    let compressed = std::thread::scope(|scope| {
        let source = Stuttering {
            data: &input,
            calls: 0,
        };
        let (mut source, queue) = c.reader(source, window(2)).unwrap();
        scope.spawn(move || queue.into_iter().for_each(|task| task.run()));
        let mut compressed = Vec::new();
        let mut failures = 0;
        while let Err(error) = source.read_to_end(&mut compressed) {
            assert_eq!(error.to_string(), "injected");
            failures += 1;
        }
        assert!(failures > 1);
        compressed
    });
    assert_eq!(compressed, expected);
}

#[test]
fn readers_hand_back_source_bytes_read_ahead_of_the_session() {
    let input = data(4 * SEGMENT);
    let mut c = compressor(1, 0);
    std::thread::scope(|scope| {
        let source = Trickle {
            data: &input,
            step: 3 * SEGMENT / 2,
        };
        let (mut source, queue) = c.reader(source, TaskCount::ONE).unwrap();
        scope.spawn(move || queue.into_iter().for_each(|task| task.run()));
        let mut head = [0; 16];
        assert!(source.read(&mut head).unwrap() > 0);
        assert!(source.read(&mut []).unwrap() == 0);
        assert!(format!("{source:?}").contains("finished: false"));
        let parts = source.into_parts();
        // The buffered bytes are exactly those just before what the source
        // has still to produce.
        let remaining = parts.inner.data.len();
        let end = input.len() - remaining;
        let start = end - parts.buffered_input.len();
        assert_eq!(parts.buffered_input, &input[start..end]);
    });
}

#[test]
fn dropping_an_adapter_closes_the_queue_and_leaves_the_compressor_usable() {
    let input = data(2 * SEGMENT + 1);
    let mut c = compressor(0, 0);
    let (mut sink, queue) = c.writer(Vec::new(), window(4)).unwrap();
    sink.write_all(&input).unwrap();
    drop(sink);
    assert!(queue.recv().is_none());
    let (source, queue) = c.reader(input.as_slice(), window(4)).unwrap();
    drop(source);
    assert!(queue.recv().is_none());
    let expected = batch(&mut c, &input);
    assert_eq!(written(&mut c, &input, 2, usize::MAX, 2), expected);
}

#[test]
fn adapter_constructors_respect_the_aggregate_memory_limit() {
    let mut c = ParallelCompressor::new(
        EncoderConfig::default(),
        ParallelConfig::default().with_aggregate_memory_limit(Some(1)),
    )
    .unwrap();
    assert!(matches!(
        c.writer(Vec::new(), TaskCount::ONE),
        Err(ParallelEncodeError::WorkerMemoryLimit)
    ));
    assert!(matches!(
        c.reader(&b""[..], TaskCount::ONE),
        Err(ParallelEncodeError::WorkerMemoryLimit)
    ));
}

#[test]
fn adapter_types_are_sendable_and_debuggable() {
    fn send<T: Send>() {}
    send::<ParallelEncoderWriter<'static, Vec<u8>>>();
    send::<ParallelEncoderReader<'static, &'static [u8]>>();
    let mut c = compressor(0, 0);
    let (sink, _queue) = c.writer(Vec::new(), TaskCount::ONE).unwrap();
    let debug = format!("{sink:?}");
    assert!(debug.contains("ParallelEncoderWriter") && debug.contains("Open"));
    drop(sink);
    let (source, _queue) = c.reader(&b"x"[..], TaskCount::ONE).unwrap();
    let debug = format!("{source:?}");
    assert!(debug.contains("ParallelEncoderReader") && debug.contains("eof: false"));
}

#[test]
fn adapters_expose_their_inner_reader_and_writer() {
    let mut c = compressor(0, 0);
    let (mut sink, _queue) = c.writer(vec![7u8], TaskCount::ONE).unwrap();
    sink.get_mut().push(8);
    assert_eq!(sink.get_ref().as_slice(), [7, 8]);
    drop(sink);
    let (mut source, _queue) = c.reader(&b"abc"[..], TaskCount::ONE).unwrap();
    *source.get_mut() = &b"ab"[..];
    assert_eq!(*source.get_ref(), b"ab");
}
