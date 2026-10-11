#![cfg(feature = "compression")]
//! Byte-for-byte differential tests against the pinned C encoder.
//!
//! Every quality is a port of `google/brotli` v1.2.0 (commit `028fb5a`), so
//! with identical settings the Rust APIs must match C streaming FINISH. Native
//! C one-shot empty/fallback rewrites are deliberately not part of this oracle.

mod support;

use support::{
    IMPLEMENTED_QUALITIES, boundary_corpora, c_compress, config, encoder, prefix_for,
    quality_number, structural_corpora,
};

/// Compares one input against the C encoder for one parameter set.
fn assert_matches_c(name: &str, data: &[u8], lgwin: u8) {
    for quality in IMPLEMENTED_QUALITIES {
        let data = prefix_for(quality, data);
        let expected = c_compress(quality_number(quality), i32::from(lgwin), data);
        let actual = encoder(quality, lgwin)
            .compress(data)
            .expect("compression failed");
        assert_eq!(
            actual,
            expected,
            "case {name}, quality {}, lgwin {lgwin}: {} bytes vs {} bytes",
            quality.get(),
            actual.len(),
            expected.len()
        );
    }
}

#[test]
fn structural_corpora_match_the_c_encoder() {
    for corpus in structural_corpora() {
        assert_matches_c(&corpus.name, &corpus.data, 22);
    }
}

#[test]
fn boundary_lengths_match_the_c_encoder() {
    for corpus in boundary_corpora() {
        assert_matches_c(&corpus.name, &corpus.data, 22);
    }
}

#[test]
fn every_window_size_matches_the_c_encoder() {
    let corpora = structural_corpora();
    for lgwin in 10..=24u8 {
        for corpus in &corpora {
            if corpus.data.len() > 300_000 {
                continue;
            }
            assert_matches_c(&corpus.name, &corpus.data, lgwin);
        }
    }
}

#[test]
fn a_reused_compressor_matches_the_c_encoder_call_after_call() {
    // The whole point of a stateful compressor is that the second call reuses
    // the first one's workspace. It has to reach the same bytes doing so.
    let corpora = structural_corpora();
    for quality in IMPLEMENTED_QUALITIES {
        let mut encoder = encoder(quality, 22);
        for corpus in &corpora {
            let data = prefix_for(quality, &corpus.data);
            let expected = c_compress(quality_number(quality), 22, data);
            let actual = encoder.compress(data).expect("compression failed");
            assert_eq!(
                actual,
                expected,
                "case {}, quality {}: reuse left the reference",
                corpus.name,
                quality.get()
            );
        }
    }
}

#[test]
fn a_reused_small_window_compressor_matches_the_c_encoder_call_after_call() {
    // Windows of at most sixteen bits route qualities five to nine through the
    // forgetful-chain match finders, whose tables a reused compressor keeps.
    // A server compressing short responses with one pooled compressor walks
    // exactly this path.
    let corpora = structural_corpora();
    for lgwin in [10u8, 13, 16] {
        for quality in IMPLEMENTED_QUALITIES {
            let mut encoder = encoder(quality, lgwin);
            for corpus in &corpora {
                let data = prefix_for(quality, &corpus.data);
                let data = &data[..data.len().min(64 * 1024)];
                let expected = c_compress(quality_number(quality), i32::from(lgwin), data);
                let actual = encoder.compress(data).expect("compression failed");
                assert_eq!(
                    actual,
                    expected,
                    "case {}, quality {}, lgwin {lgwin}: reuse left the reference",
                    corpus.name,
                    quality.get()
                );
            }
        }
    }
}

#[test]
fn a_compressor_reconfigured_across_windows_matches_the_c_encoder() {
    // A pooled compressor serving responses of different sizes declares a
    // different window for each. Reshaping the window in place, and keeping
    // the match finder whenever the plan allows, must reach the bytes a
    // compressor built for each window would. The order mixes growing and
    // shrinking windows and crosses the sixteen-bit boundary where qualities
    // five to nine switch between the chain and the bucket match finders.
    let corpora = structural_corpora();
    let windows = [10u8, 13, 22, 16, 11, 17, 24, 12, 18, 16, 10];
    for quality in IMPLEMENTED_QUALITIES {
        let mut encoder = encoder(quality, windows[0]);
        for (step, &lgwin) in windows.iter().enumerate() {
            let corpus = &corpora[step % corpora.len()];
            let data = prefix_for(quality, &corpus.data);
            let data = &data[..data.len().min(96 * 1024)];
            encoder
                .reconfigure(config(quality, lgwin))
                .expect("a legal configuration");
            let expected = c_compress(quality_number(quality), i32::from(lgwin), data);
            assert_eq!(
                encoder.compress(data).expect("compression failed"),
                expected,
                "case {}, quality {}, step {step}, lgwin {lgwin}",
                corpus.name,
                quality.get()
            );
        }
    }
}

#[test]
fn a_reused_compressor_alternating_short_and_long_inputs_matches_the_c_encoder() {
    // Inputs of at most two kibibytes start cold on short-input storage for
    // qualities two to four; a warm compressor keeps whichever finder it has.
    // Alternating sizes around that boundary has to reach the bytes a fresh
    // compressor would, call after call.
    let long = structural_corpora()
        .into_iter()
        .find(|corpus| corpus.data.len() > 16 * 1024)
        .map(|corpus| corpus.data)
        .expect("a corpus longer than sixteen kibibytes");
    let lengths = [1500usize, 9000, 2048, 2049, 300, 16 * 1024, 1024, 700];
    for lgwin in [16u8, 22] {
        for quality in IMPLEMENTED_QUALITIES {
            let mut encoder = encoder(quality, lgwin);
            for &length in &lengths {
                let data = prefix_for(quality, &long);
                let data = &data[..data.len().min(length)];
                let expected = c_compress(quality_number(quality), i32::from(lgwin), data);
                assert_eq!(
                    encoder.compress(data).expect("compression failed"),
                    expected,
                    "quality {}, lgwin {lgwin}, {length} bytes",
                    quality.get()
                );
            }
        }
    }
}

#[test]
fn a_reused_compressor_crossing_the_large_input_hint_matches_the_c_encoder() {
    // At one mebibyte the size hint moves quality four to H54 and qualities
    // five to nine to H6. A reused compressor switches only its match finder,
    // parking the old one's tables for the next switch back.
    let unit = structural_corpora()
        .into_iter()
        .find(|corpus| corpus.data.len() > 16 * 1024)
        .map(|corpus| corpus.data)
        .expect("a corpus longer than sixteen kibibytes");
    let mut large = Vec::with_capacity((1 << 20) + unit.len());
    while large.len() < (1 << 20) + 4096 {
        large.extend_from_slice(&unit);
    }
    let lengths = [
        large.len(),
        40 * 1024,
        large.len(),
        3000,
        200 * 1024,
        large.len(),
    ];
    for quality in IMPLEMENTED_QUALITIES {
        if !(4..=9).contains(&quality.get()) {
            continue;
        }
        let mut encoder = encoder(quality, 22);
        for &length in &lengths {
            let data = &large[..length];
            let expected = c_compress(quality_number(quality), 22, data);
            assert_eq!(
                encoder.compress(data).expect("compression failed"),
                expected,
                "quality {}, {length} bytes",
                quality.get()
            );
        }
    }
}

#[test]
fn reconfiguring_between_calls_matches_the_c_encoder() {
    // One compressor walked across every quality, which is the workload the
    // retention policy exists for. Each configuration still has to reach the
    // bytes a compressor built only for it would.
    let data = structural_corpora()
        .into_iter()
        .find(|corpus| corpus.data.len() > 4096)
        .map(|corpus| corpus.data)
        .expect("a corpus large enough to be worth splitting");

    let mut encoder = encoder(IMPLEMENTED_QUALITIES[0], 22);
    for quality in IMPLEMENTED_QUALITIES {
        encoder
            .reconfigure(config(quality, 22))
            .expect("a legal configuration");
        let data = prefix_for(quality, &data);
        let expected = c_compress(quality_number(quality), 22, data);
        assert_eq!(
            encoder.compress(data).expect("compression failed"),
            expected,
            "quality {} differed after a reconfigure",
            quality.get()
        );
    }
}
