//! End-to-end parallel scaling, batch and streamed, with serial C/Rust
//! baselines and explicit sizes.
//! Parallel and serial streams have different history policies; only parallel
//! task-count comparisons are equivalent compressed-output speed measurements.
#[path = "../tests/support/mod.rs"]
#[cfg(not(feature = "no_std"))]
mod support;
#[cfg(not(feature = "no_std"))]
use criterion::{BenchmarkId, Criterion, Throughput, criterion_group, criterion_main};
#[cfg(not(feature = "no_std"))]
use mbrotli::compressor::parallel::{
    BatchConfig, FileSource, ParallelCompressor, ParallelConfig, ParallelEncoderStatus,
    RandomAccessSource, SeekSource, SegmentSize, TaskCount,
};
#[cfg(not(feature = "no_std"))]
use mbrotli::{Compressor, EncoderConfig, Operation, Quality};
#[cfg(not(feature = "no_std"))]
use std::hint::black_box;

#[cfg(not(feature = "no_std"))]
fn encode(
    compressor: &mut ParallelCompressor,
    pool: &rayon::ThreadPool,
    input: &[u8],
    tasks: usize,
    out: &mut Vec<u8>,
) {
    let mut batch = compressor
        .prepare_slice(
            input,
            BatchConfig::auto(TaskCount::try_from(tasks).unwrap()),
        )
        .unwrap();
    if tasks == 1 {
        batch.run_inline().unwrap();
    } else {
        let jobs = batch.take_tasks().unwrap();
        pool.scope(|scope| {
            for job in jobs {
                scope.spawn(move |_| job.run());
            }
        });
    }
    out.clear();
    batch.finish_into(out).unwrap();
}
/// Streams `input` in 64 KiB calls through a 64 KiB output buffer, as a pipe
/// would. One task runs inline; more run on `tasks` pool executors draining
/// the session's queue, with that many parts in flight.
#[cfg(not(feature = "no_std"))]
fn encode_stream(
    compressor: &mut ParallelCompressor,
    pool: &rayon::ThreadPool,
    input: &[u8],
    tasks: usize,
    out: &mut Vec<u8>,
) {
    let (mut session, queue) = compressor
        .start(TaskCount::try_from(tasks).unwrap())
        .unwrap();
    let inline = (tasks == 1).then(|| queue.clone());
    if tasks > 1 {
        for _ in 0..tasks {
            let queue = queue.clone();
            pool.spawn(move || queue.into_iter().for_each(|task| task.run()));
        }
    }
    drop(queue);
    out.clear();
    let mut buffer = vec![0; 64 << 10];
    let mut rest = input;
    loop {
        let take = rest.len().min(64 << 10);
        let operation = if take == rest.len() {
            Operation::Finish
        } else {
            Operation::Process
        };
        let progress = session
            .process(&rest[..take], &mut buffer, operation)
            .unwrap();
        rest = &rest[progress.consumed..];
        out.extend_from_slice(&buffer[..progress.produced]);
        match progress.status {
            ParallelEncoderStatus::Finished => break,
            ParallelEncoderStatus::Pending => {
                if let Some(queue) = &inline {
                    while let Some(task) = queue.try_recv() {
                        task.run();
                    }
                }
                session.wait().unwrap();
            }
            ParallelEncoderStatus::NeedsInput | ParallelEncoderStatus::NeedsOutput => {}
        }
    }
}
#[cfg(not(feature = "no_std"))]
fn encode_source(
    compressor: &mut ParallelCompressor,
    pool: &rayon::ThreadPool,
    source: &std::sync::Arc<dyn RandomAccessSource>,
    input_len: usize,
    out: &mut Vec<u8>,
) {
    let mut batch = compressor
        .prepare_source::<dyn RandomAccessSource, _>(
            std::sync::Arc::clone(source),
            BatchConfig::memory(TaskCount::try_from(4).unwrap(), input_len * 3),
        )
        .unwrap();
    let tasks = batch.take_tasks().unwrap();
    pool.scope(|scope| {
        for task in tasks {
            scope.spawn(move |_| task.run());
        }
    });
    out.clear();
    batch.finish_into(out).unwrap();
    black_box(out);
}
#[cfg(not(feature = "no_std"))]
fn benchmarks(c: &mut Criterion) {
    let pool = rayon::ThreadPoolBuilder::new()
        .num_threads(4)
        .build()
        .unwrap();
    let text = std::fs::read("brotli-ffi/vendor/brotli/tests/testdata/alice29.txt").unwrap();
    let expand = |pattern: &[u8], size: usize| {
        pattern
            .iter()
            .copied()
            .cycle()
            .take(size)
            .collect::<Vec<_>>()
    };
    let mut seed = 1u64;
    let random: Vec<_> = (0..1 << 20)
        .map(|_| {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed as u8
        })
        .collect();
    let corpora = [
        ("tiny", b"small input".to_vec()),
        ("text-1MiB", expand(&text, 1 << 20)),
        (
            "binary-1MiB",
            expand(&(0..=255).collect::<Vec<_>>(), 1 << 20),
        ),
        ("random-1MiB", random),
        ("zeros-1MiB", vec![0; 1 << 20]),
        ("text-16MiB", expand(&text, 16 << 20)),
    ];
    for q in [0, 1, 5, 9, 11] {
        let cfg = EncoderConfig::default().with_quality(Quality::try_from(q).unwrap());
        for (name, input) in &corpora {
            let segment = if input.len() >= 8 << 20 {
                SegmentSize::DEFAULT
            } else {
                SegmentSize::try_from(256 << 10).unwrap()
            };
            let parallel = ParallelConfig::from(segment)
                .with_minimum_parallel_size(0)
                .with_max_retained_workers(4);
            let mut compressor = ParallelCompressor::new(cfg, parallel).unwrap();
            let mut out = Vec::new();
            encode(&mut compressor, &pool, input, 1, &mut out);
            let expected = out.clone();
            encode(&mut compressor, &pool, input, 4, &mut out);
            assert_eq!(out, expected);
            for tasks in [1, 4] {
                encode_stream(&mut compressor, &pool, input, tasks, &mut out);
                assert_eq!(out, expected);
            }
            assert_eq!(support::c_decompress(&out, input.len()).unwrap(), *input);
            let serial = support::c_compress(q.into(), 22, input);
            let rust = Compressor::new(cfg).unwrap().compress(input).unwrap();
            assert_eq!(rust, serial);
            assert_eq!(support::c_decompress(&serial, input.len()).unwrap(), *input);
            eprintln!(
                "q{q}/{name}: input={} parallel={} serial={} segment={}",
                input.len(),
                out.len(),
                serial.len(),
                segment.get()
            );
            let mut group = c.benchmark_group(format!("parallel/q{q}/{name}"));
            group.throughput(Throughput::Bytes(input.len() as u64));
            for tasks in [1, 4] {
                group.bench_with_input(BenchmarkId::new("tasks", tasks), &tasks, |b, &tasks| {
                    b.iter(|| {
                        encode(&mut compressor, &pool, black_box(input), tasks, &mut out);
                        black_box(&out);
                    })
                });
                group.bench_with_input(
                    BenchmarkId::new("stream-tasks", tasks),
                    &tasks,
                    |b, &tasks| {
                        b.iter(|| {
                            encode_stream(
                                &mut compressor,
                                &pool,
                                black_box(input),
                                tasks,
                                &mut out,
                            );
                            black_box(&out);
                        })
                    },
                );
                let alternate = cfg.with_quality(if q == 0 { Quality::Q1 } else { Quality::Q0 });
                compressor.reconfigure(alternate).unwrap();
                compressor.reconfigure(cfg).unwrap();
                encode(&mut compressor, &pool, input, tasks, &mut out);
                assert_eq!(out, expected);
                group.bench_with_input(
                    BenchmarkId::new("tasks-reconfigured", tasks),
                    &tasks,
                    |b, &tasks| {
                        b.iter(|| {
                            compressor.reconfigure(black_box(alternate)).unwrap();
                            compressor.reconfigure(black_box(cfg)).unwrap();
                            encode(&mut compressor, &pool, black_box(input), tasks, &mut out);
                            black_box(&out);
                        })
                    },
                );
            }
            group.bench_function("c-serial-cold", |b| {
                b.iter(|| black_box(support::c_compress(q.into(), 22, black_box(input))))
            });
            group.bench_function("rust-serial-cold", |b| {
                b.iter(|| {
                    black_box(
                        Compressor::new(cfg)
                            .unwrap()
                            .compress(black_box(input))
                            .unwrap(),
                    )
                })
            });
            if q == 5 && *name == "text-16MiB" {
                use std::{
                    io::{Cursor, Write},
                    sync::Arc,
                };
                let mut file = tempfile::tempfile().unwrap();
                file.write_all(input).unwrap();
                let positional = FileSource::try_from(file.try_clone().unwrap()).unwrap();
                let sources: [(&str, Arc<dyn RandomAccessSource>); 3] = [
                    (
                        "seek-cursor",
                        Arc::new(SeekSource::from(Cursor::new(input.clone()))),
                    ),
                    ("seek-file", Arc::new(SeekSource::from(file))),
                    ("positional-file", Arc::new(positional)),
                ];
                for (label, source) in sources {
                    encode_source(&mut compressor, &pool, &source, input.len(), &mut out);
                    assert_eq!(out, expected);
                    group.bench_function(label, |b| {
                        b.iter(|| {
                            encode_source(&mut compressor, &pool, &source, input.len(), &mut out);
                        })
                    });
                }
            }
            group.finish();
        }
    }
}
#[cfg(not(feature = "no_std"))]
criterion_group!(benches, benchmarks);
#[cfg(not(feature = "no_std"))]
criterion_main!(benches);

#[cfg(feature = "no_std")]
fn main() {}
