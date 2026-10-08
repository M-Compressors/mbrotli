#![cfg(feature = "decompression")]
mod support;

use mbrotli::{DecodeError, DecodeLimits, DecoderConfig, Decompressor, MemberMode};

#[test]
fn owned_history_matches_slice_decoding_before_at_and_after_window_wrap() {
    for (_, backend) in support::host_levels() {
        for quality in [0, 5, 11] {
            for length in [0, 1, 63, 64, 65, 1023, 1024, 1025, 4097, 16384] {
                for payload in [
                    vec![b'x'; length],
                    (0..length).map(|i| (i * 173 % 251) as u8).collect(),
                ] {
                    let compressed = support::c_compress_native_one_shot(quality, 10, &payload);
                    let mut decoder = Decompressor::builder(DecoderConfig::default())
                        .with_backend(backend)
                        .build()
                        .unwrap();
                    let owned = decoder.decompress(&compressed).unwrap();
                    assert_eq!(owned, payload);
                    let mut slice = vec![0; length];
                    decoder
                        .decompress_to_slice(&compressed, &mut slice)
                        .unwrap();
                    assert_eq!(slice, owned);
                    assert_eq!(decoder.decompress(&compressed).unwrap(), owned);
                    // Reuse must not mutate the transferred allocation.
                    assert_eq!(owned, payload);
                }
            }
        }
    }
}

#[test]
fn collected_output_keeps_limits_truncation_and_append_rollback() {
    for quality in [0, 5, 11] {
        let payload = vec![b'z'; 4097];
        let compressed = support::c_compress_native_one_shot(quality, 22, &payload);
        for limit in [0, 1, 4096, 4097, 4098] {
            let config = DecoderConfig::default()
                .with_limits(DecodeLimits::default().with_max_output_bytes(Some(limit)));
            let result = Decompressor::new(config).unwrap().decompress(&compressed);
            if limit < payload.len() as u64 {
                assert!(matches!(
                    result,
                    Err(DecodeError::OutputLimitExceeded { .. })
                ));
            } else {
                assert_eq!(result.unwrap(), payload);
            }
        }
        for end in 0..compressed.len() {
            let mut decoder = Decompressor::new(DecoderConfig::default()).unwrap();
            let mut output = Vec::new();
            assert!(
                decoder
                    .decompress_into(&compressed[..end], &mut output)
                    .is_err()
            );
            assert!(output.is_empty());
        }
        let mut tailed = compressed.clone();
        tailed.push(0);
        let mut decoder = Decompressor::new(DecoderConfig::default()).unwrap();
        assert!(matches!(
            decoder.decompress(&tailed),
            Err(DecodeError::TrailingData { .. })
        ));
        let mut prefix = b"prefix".to_vec();
        assert!(decoder.decompress_into(&tailed, &mut prefix).is_err());
        assert_eq!(prefix, b"prefix");
    }
}

#[test]
fn concatenated_owned_members_keep_separate_histories() {
    let a = vec![b'a'; 4097];
    let b = vec![b'b'; 1025];
    let mut compressed = support::c_compress_native_one_shot(5, 10, &a);
    compressed.extend(support::c_compress_native_one_shot(0, 10, &b));
    let config = DecoderConfig::default().with_member_mode(MemberMode::Concatenated);
    assert_eq!(
        Decompressor::new(config)
            .unwrap()
            .decompress(&compressed)
            .unwrap(),
        [a, b].concat()
    );
}

#[test]
fn stored_short_headers_match_streaming_for_every_bit_mutation() {
    for window in 18..=24 {
        for length in [1usize, 2, 255, 256, 65535, 65536] {
            let header = 0x80_0001u32 | ((window - 17) << 1) | ((length as u32 - 1) << 7);
            let mut input = header.to_le_bytes()[..3].to_vec();
            input.extend((0..length).map(|i| i as u8));
            input.push(3);
            let expected = input[3..3 + length].to_vec();
            let config = DecoderConfig::default();
            assert_eq!(
                Decompressor::new(config)
                    .unwrap()
                    .decompress(&input)
                    .unwrap(),
                expected
            );
            let mut output = vec![0; length];
            Decompressor::new(config)
                .unwrap()
                .decompress_to_slice(&input, &mut output)
                .unwrap();
            assert_eq!(output, expected);
            if length == 255 {
                for bit in 0..32 {
                    let byte = if bit < 24 { bit / 8 } else { input.len() - 1 };
                    input[byte] ^= 1 << (bit % 8);
                    let owned = Decompressor::new(config).unwrap().decompress(&input);
                    // Appending into a nonempty vector exercises the full driver.
                    let mut baseline = vec![42];
                    let result = Decompressor::new(config)
                        .unwrap()
                        .decompress_into(&input, &mut baseline);
                    match (owned, result) {
                        (Ok(bytes), Ok(range)) => assert_eq!(bytes, baseline[range]),
                        (Err(a), Err(b)) => {
                            assert_eq!(std::mem::discriminant(&a), std::mem::discriminant(&b));
                            assert_eq!(a.to_string(), b.to_string());
                        }
                        pair => panic!("stored/driver mismatch: {pair:?}"),
                    }
                    input[byte] ^= 1 << (bit % 8);
                }
            }
        }
    }
}

/// Mixed text, runs and noise of `len` bytes.
fn mixed(len: usize) -> Vec<u8> {
    let mut rng = support::Rng::new(0x0dec_0de5);
    let mut data = Vec::with_capacity(len);
    while data.len() < len {
        match rng.next_u8() % 3 {
            0 => data.extend_from_slice(b"appended output keeps its history. "),
            1 => data.extend(std::iter::repeat_n(rng.next_u8(), 300)),
            _ => data.extend(rng.bytes(80, 256)),
        }
    }
    data.truncate(len);
    data
}

#[test]
fn appending_decodes_into_the_vector_across_many_growth_steps() {
    // A reused decoder and a vector with a prefix take the appending path,
    // which decodes the first member straight into the vector's new tail.
    let mut decoder = Decompressor::new(DecoderConfig::default()).unwrap();
    for (len, quality, lgwin) in [(1 << 20, 1, 22), (1 << 20, 9, 22), (300_000, 5, 16)] {
        let payload = mixed(len);
        let compressed = support::c_compress(quality, lgwin, &payload);
        let mut output = b"prefix".to_vec();
        let range = decoder.decompress_into(&compressed, &mut output).unwrap();
        assert_eq!(range, 6..6 + len);
        assert_eq!(&output[..6], b"prefix");
        assert_eq!(output[range], payload);
        // A reused decoder and allocation decode the same bytes again.
        output.clear();
        assert_eq!(
            decoder.decompress_into(&compressed, &mut output).unwrap(),
            0..len
        );
        assert_eq!(output, payload);
    }
}

#[test]
fn appending_concatenated_members_delivers_each_after_the_previous() {
    let config = DecoderConfig::default().with_member_mode(MemberMode::Concatenated);
    let mut decoder = Decompressor::new(config).unwrap();
    let first = mixed(100_000);
    let second = b"a second member after the first. ".repeat(4000);
    let mut compressed = support::c_compress(5, 22, &first);
    compressed.extend(support::c_compress(9, 18, &second));
    let mut output = vec![7];
    let range = decoder.decompress_into(&compressed, &mut output).unwrap();
    assert_eq!(output[0], 7);
    assert_eq!(output[range], [first, second].concat());
}

#[test]
fn appending_rolls_back_a_corrupt_or_truncated_stream() {
    let mut decoder = Decompressor::new(DecoderConfig::default()).unwrap();
    let payload = mixed(200_000);
    let compressed = support::c_compress(5, 22, &payload);
    let mut output = b"kept".to_vec();
    let truncated = &compressed[..compressed.len() - 1];
    assert!(matches!(
        decoder.decompress_into(truncated, &mut output),
        Err(DecodeError::UnexpectedEndOfInput)
    ));
    assert_eq!(output, b"kept");
    let mut trailing = compressed.clone();
    trailing.push(0);
    assert!(matches!(
        decoder.decompress_into(&trailing, &mut output),
        Err(DecodeError::TrailingData { .. })
    ));
    assert_eq!(output, b"kept");
}

#[test]
fn appending_a_stored_member_copies_it_and_respects_policies() {
    let mut rng = support::Rng::new(0x0057_02ed);
    let payload = rng.bytes(50_000, 256);
    let compressed = support::c_compress(9, 22, &payload);
    let mut decoder = Decompressor::new(DecoderConfig::default()).unwrap();
    let mut output = b"head".to_vec();
    let range = decoder.decompress_into(&compressed, &mut output).unwrap();
    assert_eq!(range, 4..4 + payload.len());
    assert_eq!(output[range], payload);

    // Limits and trailing bytes are the session's to report.
    let limits = DecodeLimits::default().with_max_output_bytes(Some(1000));
    let mut limited = Decompressor::new(DecoderConfig::default().with_limits(limits)).unwrap();
    let mut output = b"head".to_vec();
    assert!(matches!(
        limited.decompress_into(&compressed, &mut output),
        Err(DecodeError::OutputLimitExceeded { limit: 1000 })
    ));
    assert_eq!(output, b"head");
    let mut trailing = compressed.clone();
    trailing.push(0);
    assert!(matches!(
        decoder.decompress_into(&trailing, &mut output),
        Err(DecodeError::TrailingData { .. })
    ));
    assert_eq!(output, b"head");
}

#[test]
fn appending_reserves_in_proportion_to_the_output() {
    // Linear appends zero the vector in small steps; the reservation must
    // still grow per chunk, not per step, or a 500 KB output would leave
    // tens of mebibytes reserved.
    let mut decoder = Decompressor::new(DecoderConfig::default()).unwrap();
    for (quality, data) in [(5, mixed(500_000)), (9, b"runs ".repeat(100_000))] {
        let compressed = support::c_compress(quality, 22, &data);
        let mut warm = Vec::new();
        decoder.decompress_into(&compressed, &mut warm).unwrap();
        let mut output = Vec::new();
        decoder.decompress_into(&compressed, &mut output).unwrap();
        assert_eq!(output, data);
        assert!(
            output.capacity() <= 4 * data.len(),
            "{} bytes reserved for {}",
            output.capacity(),
            data.len()
        );
    }
}
