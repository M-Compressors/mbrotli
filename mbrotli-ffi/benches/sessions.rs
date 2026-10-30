//! End-to-end streaming C calls (creation and destruction included), with
//! identical input, q5/w22, 4 KiB output chunks and Finish schedules.
use criterion::{BenchmarkId, Criterion, Throughput, criterion_group, criterion_main};
use google_brotli_ffi as c;
use mbrotli_ffi::*;
use std::hint::black_box;
use std::ptr::null_mut;

fn encode(input: &[u8], output: &mut [u8], google: bool) -> usize {
    // SAFETY: states are live and exclusive, all pointers/counts are disjoint,
    // buffer extents are valid and each state is destroyed exactly once.
    unsafe {
        let mut remaining = input;
        let mut total = 0;
        let ours = if google {
            null_mut()
        } else {
            mbrotli_encoder_session_create(5, 22)
        };
        let theirs = if google {
            c::BrotliEncoderCreateInstance(None, None, null_mut())
        } else {
            null_mut()
        };
        if google {
            assert!(!theirs.is_null());
            assert_eq!(
                c::BrotliEncoderSetParameter(theirs, c::BROTLI_PARAM_QUALITY, 5),
                c::BROTLI_TRUE
            );
            assert_eq!(
                c::BrotliEncoderSetParameter(theirs, c::BROTLI_PARAM_LGWIN, 22),
                c::BROTLI_TRUE
            );
        } else {
            assert!(!ours.is_null());
        }
        loop {
            let cap = (output.len() - total).min(4096);
            assert!(cap > 0);
            let (mut read, mut written) = (remaining.len(), cap);
            let finished = if google {
                let mut next_in = remaining.as_ptr();
                let mut next_out = output.as_mut_ptr().add(total);
                assert_eq!(
                    c::BrotliEncoderCompressStream(
                        theirs,
                        c::BROTLI_OPERATION_FINISH,
                        &mut read,
                        &mut next_in,
                        &mut written,
                        &mut next_out,
                        null_mut()
                    ),
                    c::BROTLI_TRUE
                );
                read = remaining.len() - read;
                written = cap - written;
                c::BrotliEncoderIsFinished(theirs) != 0
            } else {
                let status = mbrotli_encoder_session_process(
                    ours,
                    remaining.as_ptr(),
                    &mut read,
                    output.as_mut_ptr().add(total),
                    &mut written,
                    2,
                );
                assert!(matches!(
                    status,
                    MbrotliResult::NeedsOutput | MbrotliResult::Finished
                ));
                status == MbrotliResult::Finished
            };
            remaining = &remaining[read..];
            total += written;
            if finished {
                break;
            }
        }
        assert!(remaining.is_empty());
        if google {
            c::BrotliEncoderDestroyInstance(theirs);
        } else {
            mbrotli_encoder_session_destroy(ours);
        }
        total
    }
}

fn decode(input: &[u8], output: &mut [u8], google: bool) -> usize {
    // SAFETY: same allocation, exclusivity and pointer invariants as encode.
    unsafe {
        let ours = if google {
            null_mut()
        } else {
            mbrotli_decoder_session_create()
        };
        let theirs = if google {
            c::BrotliDecoderCreateInstance(None, None, null_mut())
        } else {
            null_mut()
        };
        assert!(if google {
            !theirs.is_null()
        } else {
            !ours.is_null()
        });
        let mut remaining = input;
        let mut total = 0;
        loop {
            let cap = (output.len() - total).min(4096);
            let (mut read, mut written) = (remaining.len(), cap);
            let finished = if google {
                let mut next_in = remaining.as_ptr();
                let mut next_out = output.as_mut_ptr().add(total);
                let status = c::BrotliDecoderDecompressStream(
                    theirs,
                    &mut read,
                    &mut next_in,
                    &mut written,
                    &mut next_out,
                    null_mut(),
                );
                assert!(
                    status == c::BROTLI_DECODER_RESULT_SUCCESS
                        || status == c::BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT
                );
                read = remaining.len() - read;
                written = cap - written;
                status == c::BROTLI_DECODER_RESULT_SUCCESS
            } else {
                let status = mbrotli_decoder_session_process(
                    ours,
                    remaining.as_ptr(),
                    &mut read,
                    output.as_mut_ptr().add(total),
                    &mut written,
                    2,
                );
                assert!(matches!(
                    status,
                    MbrotliResult::NeedsOutput | MbrotliResult::Finished
                ));
                status == MbrotliResult::Finished
            };
            remaining = &remaining[read..];
            total += written;
            if finished {
                break;
            }
            assert!(read + written > 0);
        }
        assert!(remaining.is_empty());
        if google {
            c::BrotliDecoderDestroyInstance(theirs);
        } else {
            mbrotli_decoder_session_destroy(ours);
        }
        total
    }
}

fn sessions(c: &mut Criterion) {
    let text = include_bytes!("../../brotli-ffi/vendor/brotli/tests/testdata/alice29.txt");
    let binary = include_bytes!("../../brotli-ffi/vendor/brotli/tests/testdata/random_org_10k.bin");
    let repetitive = vec![b'x'; 1 << 20];
    for (name, input) in [
        ("tiny", &text[..64]),
        ("text", text.as_slice()),
        ("binary", binary.as_slice()),
        ("repetitive", repetitive.as_slice()),
    ] {
        let mut wire = vec![0; input.len() * 2 + 1024];
        let mut reference = vec![0; wire.len()];
        let ours = encode(input, &mut wire, false);
        let theirs = encode(input, &mut reference, true);
        assert_eq!(&wire[..ours], &reference[..theirs]);
        eprintln!("{name}: input={} compressed={ours}", input.len());
        let mut decoded = vec![0; input.len()];
        for google in [false, true] {
            assert_eq!(decode(&wire[..ours], &mut decoded, google), input.len());
            assert_eq!(decoded, input);
        }
        let mut group = c.benchmark_group(format!("session/{name}"));
        group.throughput(Throughput::Bytes(input.len() as u64));
        for (label, google) in [("mbrotli", false), ("google", true)] {
            group.bench_function(BenchmarkId::new("encode", label), |b| {
                b.iter(|| encode(black_box(input), black_box(&mut reference), google))
            });
            group.bench_function(BenchmarkId::new("decode", label), |b| {
                b.iter(|| decode(black_box(&wire[..ours]), black_box(&mut decoded), google))
            });
        }
        group.finish();
    }
}
criterion_group!(benches, sessions);
criterion_main!(benches);
