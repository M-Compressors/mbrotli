# Fuzz campaign records

Completed AFL++ campaigns, newest first. Each record states the revision,
host, duration and outcome of one bounded run. They are historical evidence
for [compatibility and validation](correctness.md), not a guarantee for later
revisions. To run a campaign yourself, follow the
[AFL guide](../fuzz/afl/README.md); [fuzzing mechanics](../architecture/fuzzing.md)
describes the targets and oracles.

## Interrupted AFL campaign — 2026-10-09

After the distance-cache prefilter (q7–q11), the `u8x32` dictionary compare and
the UTF-8 early exit (q10/q11), fresh builds of the uncommitted working tree on
v0.5.6 ran `campaign.sh` with `CAMPAIGN_PARALLEL=1` (24 stable and 26
experimental compression-side targets) and `decoder-campaign.sh` (7 stable and
8 experimental decoder targets): **65 AFL++ workers** on the i7-13700KF/WSL2
host's 24 threads, fixed 30 s and 5 s timeouts. The run was planned for 4.5
hours and stopped by hand after **1 h 40 min** (5,988–6,066 s per worker) to
free the host for benchmarks.

| Group | Workers | Executions |
| --- | ---: | ---: |
| Encoder, stable | 24 | 9,825,192 |
| Encoder, experimental | 26 | 13,365,353 |
| Decoder, stable | 7 | 59,577,320 |
| Decoder, experimental | 8 | 106,854,256 |
| **Total** | **65** | **189,622,121** |

No crashes, hangs or correctness-oracle failures were recorded; stability
stayed at or above 99.39%. The changed boundaries are slow under
instrumentation on this oversubscribed host: `q11_roundtrip` and
`q10_roundtrip` reached 10,067–14,330 executions, `encoder_session` 16,578, so
this run is shallow for q10/q11. The committed regression corpus replayed
cleanly through `cargo afl test` in both builds before the campaign.

## Four-hour AFL campaign — 2026-10-01

After the greedy-encoder changes of 2026-10-01 (slice-fed range stores for the
deep q7–q9 bucket shapes, a flat position and tag index for q5–q6, slice-fed
literal splitting in the meta-block builder), fresh builds of the working tree
ran for **4 hours**: `campaign.sh` with `CAMPAIGN_PARALLEL=1` (24 stable and 26
experimental compression-side targets) and `decoder-campaign.sh` (7 stable and
8 experimental decoder targets), **65 AFL++ workers** on the
i7-13700KF/WSL2 host's 24 threads, with the scripts' fixed 30 s and 5 s
timeouts. Every worker ran its full 14,400 s.

| Group | Workers | Executions |
| --- | ---: | ---: |
| Encoder, stable | 24 | 29,978,741 |
| Encoder, experimental | 26 | 28,474,966 |
| Decoder, stable | 7 | 148,112,839 |
| Decoder, experimental | 8 | 179,724,677 |
| **Total** | **65** | **386,291,223** |

No crashes or correctness-oracle failures were recorded; stability stayed at or
above 99.39%. `encoder_session` (stable) saved five hangs, none of them a loop
or touching the changed code. Four are quality 11 over 128 KiB in 4 KiB chunks:
one finishes in 12.7 s of CPU time standalone under instrumentation, 35.5 s of
wall time on the oversubscribed host, above the 30 s timeout. The fifth is the
quality 10, one-byte-chunk case of the 2026-09-27 campaign: 125 s of CPU time
standalone, again search cost scaling with payload length. Both inputs exit
cleanly. The committed regression corpus replayed cleanly through
`cargo afl test` in both builds before the campaign.

## Decoder command-loop smoke campaign — 2026-09-30

After the command-loop changes of 2026-09-30 (slice-cursor refill,
per-block-type distance tables, snapshot copies tried before the exact-extent
test, one combined copy-limit test, no per-write ring-end test for linear
history), `decoder-campaign.sh` ran every decoder target of both builds for
**20 minutes** with its fixed 5 s timeout: 15 target/build pairs, 22,352,094
stable and 29,512,959 experimental executions (51,865,053 in total). No
crashes or hangs were recorded; stability stayed at or above 99.39%. The
committed regression corpus replays cleanly through `cargo afl test` in both
builds.

## Eight-hour AFL campaign and follow-up — 2026-09-27/28

After uninitialized output landed (`17b3d315`), every fuzz target of both
feature builds ran for **8 hours on 12 threads** of the i7-13700KF/WSL2 host:
66 target/build pairs (30 stable, 36 experimental, compression and
decompression) scheduled through twelve slots. The 14 pairs whose oracles
reach uninitialized output (`encoder_session`, `decoder_session`,
`streaming_equivalence`, `output_capacity`, `decompress`, `decode_streaming`,
`c_abi`) ran 2 hours each and the others 75 minutes, with the fixed timeouts of
`campaign.sh` (30 s) and `decoder-campaign.sh` (5 s).

| Build | Pairs | Executions |
| --- | ---: | ---: |
| Stable | 30 | 103,259,280 |
| Experimental | 36 | 170,088,423 |
| **Total** | **66** | **273,347,703** |

No crashes or correctness-oracle failures were recorded; stability stayed at or
above 99.38%. `encoder_session` saved one hang per build. Both inputs finish
in about 120 s standalone under instrumentation, and the time scales linearly
with payload length (14, 31, 60 and 119 s for an eighth, a quarter, a half and
all of it): quality 10 with one-byte chunks and a flush every three blocks,
over roughly ten compressions of a 125 KiB payload. That is search cost, not a
loop. AFL++ 4.40 ended four workers at start-up with an expired `-V` limit
(reporting "total runtime infty days"); each was rerun for its full slot.

Performance fixes to the decoder and the C ABI followed, and the twelve
decoder and C ABI target/build pairs they touch ran for **30 minutes** more on
12 threads (36,517,398 executions). `decompress` saved nine crashes, all one
bug that predates uninitialized output: a session growing its history ring for
the whole of a long literal insert failed a workspace limit that
`decompress_to_slice` into the same buffer never meets. The minimized input is
`fuzz/afl/regressions/decompress/crash-long-insert-ring-growth.bin` and the
`a_long_insert_grows_the_ring_only_for_output_the_call_can_hold` test; both
failed before the fix, and all nine crashes pass after it. On the final tree,
`decompress`, `decoder_session`, `decode_streaming` and `c_abi` in both builds,
`decode_io_limits` and `decode_lifecycle` in the stable build, and
`framed_decode` and `decode_serialized` in the experimental one ran
**15 minutes** more (25,065,107 executions) with no crashes or hangs.

## Six-hour AFL campaign — 2026-09-26

After the decoder changes of 2026-09-26 (unmasked refill, literal tail runs,
linear slice history), every fuzz target ran for **6 hours** from fresh builds of
the working tree: `campaign.sh` with `CAMPAIGN_PARALLEL=1` (22 stable and 24
experimental encoder-side targets), `decoder-campaign.sh` (6 stable and 7
experimental decoder targets) and the three framed targets that neither script
covers (`framed_decode`, `framed_encode`, `framed_roundtrip`, experimental build),
for **62 AFL++ workers** on the i7-13700KF/WSL2 host's 24 threads.

| Group | Workers | Executions |
| --- | ---: | ---: |
| Encoder, stable | 22 | 43,668,477 |
| Encoder, experimental | 24 | 48,598,336 |
| Decoder, stable | 6 | 204,316,217 |
| Decoder, experimental | 7 | 327,495,724 |
| Framed, experimental | 3 | 6,915,108 |
| **Total** | **62** | **630,993,862** |

No crashes or correctness-oracle failures were recorded; stability stayed at or
above 99.38%. The `decompress` target now also checks that
`decompress_to_slice` matches ring-backed session delivery, byte for byte.

`framed_decode` saved two hangs at its 5 s timeout. Both inputs finish in 0.57 s
standalone under instrumentation, so the timeouts came from oversubscription,
not an unbounded loop. Their time goes to `framing::core::Engine::framing_bytes`:
it recomputes workspace accounting over every chunk and metadata record on
each budget check, which is quadratic in the number of records. This campaign
found that slow path in the experimental framed decoder; it is open, and it is
not a decoding error.

## Eight-hour AFL campaign — 2026-09-11

The recorded campaign exercised compression and decompression in stable and
experimental builds for **8 hours**, using **59 AFL++ workers** on an
Intel Core i7-13700KF/WSL2 host. Across **914,882,807 executions**, no crashes or
correctness-oracle failures were recorded. Checks included C compatibility,
round trips, API/chunking/backend equivalence, dictionaries, limits and lifecycle.

The run found one allocation-related slowdown in `large_window` (19 saved hangs).
It was fixed and covered by [`hq_forest_allocation`](../tests/hq_forest_allocation.rs).
Both affected feature builds were then fuzzed for **45 minutes each**, starting
with the saved inputs: **18,400 further executions, no crashes or hangs**.
This is a completed validation record, not a guarantee for all possible inputs
or later revisions.

