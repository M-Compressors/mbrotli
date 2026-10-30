#!/usr/bin/env python3
"""Run the SIMD and uninitialized-memory tests under Miri or AddressSanitizer.

Tests are chosen by name prefix from the binary's own `--list`, then run with
`--exact`, so a prefix cannot also match an unrelated module by substring, and
a prefix that selects no test, or whose every test is ignored, fails the run
instead of passing silently.

    scripts/check_simd_uninit.py miri [--target TRIPLE] [--jobs N] [--batch N] [--shard K/N]
    scripts/check_simd_uninit.py asan [--target TRIPLE] [--jobs N] [--batch N] [--shard K/N]

Each process runs a batch of up to `--batch` tests: starting `cargo miri` costs
seconds, which over hundreds of one-test processes outweighs the tests. A
batch takes every n-th test of its binary, so the slow tests of one module
spread over several batches. `--shard K/N` runs every N-th test, starting
from the K-th, so CI can split the run across runners; the tests in `SLOW`
are dealt first, one process each, and the doc tests run in shard 1.

Miri reaches only the SIMD levels the build enables at compile time; set
`RUSTFLAGS=-Ctarget-cpu=...` (and a separate `CARGO_TARGET_DIR`) to select
them. Under Miri, `RUSTDOCFLAGS` defaults to `RUSTFLAGS`, so the doc tests
see the same levels. AddressSanitizer runs natively and reaches every level
the host detects.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import math
import os
import re
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]

# Unit-test modules that hold a SIMD kernel, dispatch one across backends, or
# write to or read from `MaybeUninit` memory.
LIB = [
    "backend::tests::",
    "compressor::core::cache_probe::tests::",
    "compressor::core::fast::",
    "compressor::core::greedy::backward_references::tests::",
    "compressor::core::greedy::encoder::tests::",
    "compressor::core::greedy::hashers::tests::",
    "compressor::core::hq::block_splitter::tests::",
    "compressor::core::hq::encoder::tests::",
    "compressor::core::hq::h10::tests::",
    "compressor::core::hq::zopfli::tests::",
    "compressor::core::stream::tests::",
    "compressor::session::tests::",
    "decompressor::core::session::tests::",
    "decompressor::core::stream::tests::",
    "shared::baseline::tests::",
    "shared::command::tests::",
    "shared::dictionary::all_matches::tests::",
    "shared::match_len::tests::",
    "shared::ringbuffer::tests::",
    "shared::scan::tests::",
    "shared::uninit::tests::",
]

# Integration tests: the binary and the name prefix of the tests to run.
# `encode_uninit` and `decode_uninit` compare against the C oracle on large
# streams, which Miri can neither call nor afford; `uninit_output` covers the
# same entry points for it, on destinations that start uninitialized.
TESTS = {
    "miri": [
        ("decompress_golden", ""),
        ("parallel_stream", "process_uninit_on_an_empty_destination_"),
        ("parallel_stream", "process_uninit_reports_a_failed_stream_"),
        ("uninit_output", ""),
    ],
    "asan": [
        ("decode_uninit", ""),
        ("decompress_golden", ""),
        ("encode_uninit", ""),
        ("parallel_stream", "process_uninit_"),
        ("parallel_stream", "owned_process_uninit_"),
        ("uninit_output", ""),
    ],
}

# Public examples that hand `MaybeUninit` output to the codecs.
DOC = "uninit"

# Miri has no shim for two Neon intrinsics `fearless_simd` uses:
# `vsliq_n_u8` (`mask8x32::to_bitmask`) and `vminq_f64` (`f64x2::min`). Unit
# tests that reach them carry `cfg_attr(all(miri, target_arch = "aarch64"),
# ignore)`; doc tests cannot, so they are skipped here by name.
MIRI_AARCH64_DOC_SKIPS = [
    "compressor::session::EncoderSession",
    "compressor::parallel::session::ParallelEncoderSession",
]

# Tests that take Miri minutes, slowest first, by the "slowest tests" report
# on x86-64. They are dealt to the shards before any other test, so no shard
# draws two of the slowest, and each runs in a process of its own, started
# first. A name that no longer exists, or a configuration that ignores it, is
# skipped; refresh the list from the report when it drifts.
SLOW = [
    "backend::tests::every_host_backend_matches_scalar_across_qualities_windows_and_boundaries",
    "compressor::core::hq::encoder::tests::every_backend_produces_the_same_stream",
    "compressor::core::fast::q0::tests::small_final_fragments_match_full_encoding_on_every_backend",
    "compress_to_uninit_initializes_the_stream_it_reports_at_every_quality",
    "decompress_to_uninit_initializes_what_it_decodes",
    "compressor::core::hq::h10::tests::the_vector_short_scan_agrees_with_the_byte_walk_on_every_backend",
    "encoder_process_uninit_initializes_every_reported_prefix",
    "decoder_process_uninit_initializes_every_reported_prefix",
    "shared::match_len::tests::the_outlined_scans_agree_with_the_inlined_one_on_every_level",
    "decompressor::core::stream::tests::vector_copies_match_snapshots_for_every_host_backend_and_ring_boundary",
    "compressor::core::greedy::encoder::tests::every_backend_produces_the_same_stream",
    "parallel_encoder_golden_decodes_without_an_encoder_or_std_dependency",
]

# One line per test of libtest's pretty output, with `--report-time`.
OUTCOME = re.compile(r"^test (.+) \.\.\. (ok|FAILED|ignored)(?: <([\d.]+)s>)?", re.MULTILINE)
# Arguments every test process passes to libtest. `--report-time` is
# unstable; under Miri it reports Miri's virtual clock, which counts executed
# work rather than wall time but ranks the tests all the same.
LIBTEST = ["--color", "never", "-Zunstable-options", "--report-time"]


def host() -> str:
    output = subprocess.run(["rustc", "-vV"], capture_output=True, text=True, check=True)
    return next(line.split()[1] for line in output.stdout.splitlines() if line.startswith("host:"))


def cargo(tool: str, target: str, selection: list[str]) -> list[str]:
    if tool == "miri":
        return ["cargo", "+nightly", "miri", "test", "--target", target, *selection]
    return ["cargo", "+nightly", "test", "--release", "--target", target, *selection]


def environment(tool: str) -> dict[str, str]:
    env = dict(os.environ)
    if tool == "miri":
        # Miri otherwise adds random error to `log2` and other float
        # functions, which breaks exact cost comparisons.
        flags = env.get("MIRIFLAGS", "")
        if "-Zmiri-deterministic-floats" not in flags:
            env["MIRIFLAGS"] = f"{flags} -Zmiri-deterministic-floats".strip()
        # A doc test built without the library's target features calls its
        # SIMD kernels without them, which Miri reports as undefined behavior.
        if "RUSTFLAGS" in env and "RUSTDOCFLAGS" not in env:
            env["RUSTDOCFLAGS"] = env["RUSTFLAGS"]
    else:
        for name in ["RUSTFLAGS", "RUSTDOCFLAGS"]:
            flags = env.get(name, "")
            if "-Zsanitizer=address" not in flags:
                env[name] = f"{flags} -Zsanitizer=address".strip()
    return env


def listed(tool: str, target: str, env: dict[str, str], selection: list[str],
           ignored: bool = False) -> list[str]:
    command = cargo(tool, target, selection) + ["--", "--list", "--format", "terse"]
    if ignored:
        command.append("--ignored")
    output = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True)
    if output.returncode != 0:
        sys.exit(f"listing {' '.join(selection)} failed:\n{output.stderr}")
    return [line.removesuffix(": test") for line in output.stdout.splitlines()
            if line.endswith(": test")]


def runnable(tool: str, target: str, env: dict[str, str], selection: list[str]) -> list[str]:
    """Lists the tests of one binary that this configuration does not ignore."""
    ignored = set(listed(tool, target, env, selection, ignored=True))
    return [name for name in listed(tool, target, env, selection) if name not in ignored]


def run(command: list[str], env: dict[str, str]) -> tuple[int, str, str, float]:
    """Runs one test command; returns its exit code, its standard output, its
    whole log and its wall time in seconds."""
    start = time.monotonic()
    output = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True)
    return (output.returncode, output.stdout, output.stdout + output.stderr,
            time.monotonic() - start)


def shard(value: str) -> tuple[int, int]:
    index, _, count = value.partition("/")
    try:
        index, count = int(index), int(count)
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected K/N, got {value!r}")
    if not 1 <= index <= count:
        raise argparse.ArgumentTypeError(f"shard {index} is outside 1..{count}")
    return index, count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("tool", choices=["miri", "asan"])
    parser.add_argument("--target", default=host())
    parser.add_argument("--ffi-only", action="store_true", help="run only C session uninitialized-memory tests")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    parser.add_argument("--batch", type=int, default=4, help="tests per process")
    parser.add_argument("--shard", type=shard, default=(1, 1), help="K/N: run the K-th of N shards")
    parser.add_argument("--slowest", type=int, default=10, help="slow tests to report")
    args = parser.parse_args()
    env = environment(args.tool)
    start = time.monotonic()

    # The FFI package has its own integration binary and private panic-guard tests.
    # Run it on shard 1, or alone for a focused local validation.
    if args.shard[0] == 1 or args.ffi_only:
        for selection, prefix in [(["--test", "sessions"], ""),
                                  (["--lib"], "core::sessions::tests::")]:
            selection = ["-p", "mbrotli-ffi", *selection]
            chosen = [name for name in runnable(args.tool, args.target, env, selection)
                      if name.startswith(prefix)]
            if not chosen:
                sys.exit(f"no runnable C session tests match {selection} {prefix}")
            subprocess.run(cargo(args.tool, args.target, [*selection, "--", "--exact", *chosen]),
                           cwd=root, env=env, check=True)
    if args.ffi_only:
        return

    build = cargo(args.tool, args.target, ["--lib", "--no-run"])
    tests = TESTS[args.tool]
    binaries = sorted({binary for binary, _ in tests})
    build += [arg for name in binaries for arg in ["--test", name]]
    subprocess.run(build, cwd=root, env=env, check=True)

    selections = [["--lib"]] + [["--test", name] for name in binaries]
    with ThreadPoolExecutor(args.jobs) as pool:
        names = dict(zip(map(tuple, selections), pool.map(
            lambda selection: runnable(args.tool, args.target, env, selection), selections)))

    # Every selected test, under the prefix that chose it.
    groups: dict[str, list[tuple[tuple[str, ...], str]]] = {}
    for prefix in LIB:
        groups[prefix] = [(("--lib",), name) for name in names[("--lib",)]
                          if name.startswith(prefix)]
    for binary, prefix in tests:
        selection = ("--test", binary)
        groups[f"{binary}::{prefix}"] = [(selection, name) for name in names[selection]
                                         if name.startswith(prefix)]
    empty = [label for label, chosen in groups.items() if not chosen]
    if empty:
        sys.exit(f"no test that runs here matches: {', '.join(empty)}")

    index, count = args.shard
    owner = {test: label for label, chosen in groups.items() for test in chosen}
    slow = sorted((test for test in owner if test[1] in SLOW), key=lambda test: SLOW.index(test[1]))
    dealt = slow + [test for test in owner if test[1] not in SLOW]
    mine = [test for position, test in enumerate(dealt) if position % count == index - 1]
    jobs: list[tuple[list[str], list[tuple[tuple[str, ...], str]]]] = [
        (cargo(args.tool, args.target, [*test[0], "--", *LIBTEST, "--exact", test[1]]), [test])
        for test in mine if test in slow
    ]
    for selection in names:
        chosen = [test for test in mine if test[0] == selection and test not in slow]
        batches = math.ceil(len(chosen) / max(args.batch, 1))
        for first in range(batches):
            batch = chosen[first::batches]
            jobs.append((cargo(args.tool, args.target, [
                *selection, "--", *LIBTEST, "--exact", *[name for _, name in batch]
            ]), batch))
    if index == 1:
        skips = (MIRI_AARCH64_DOC_SKIPS
                 if args.tool == "miri" and args.target.startswith("aarch64") else [])
        jobs.append((cargo(args.tool, args.target, [
            "--doc", "--", *LIBTEST, DOC,
            *[arg for skip in skips for arg in ["--skip", skip]]
        ]), []))

    # The slow tests first, then the longest batches, so the pool does not
    # end on one. The sort is stable, so the slow tests keep their order.
    jobs.sort(key=lambda job: (not set(job[1]) & set(slow), -len(job[1])))
    with ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda job: run(job[0], env), jobs))

    failed = False
    outcomes: dict[tuple[tuple[str, ...], str], str] = {}
    timings: list[tuple[float, str]] = []
    for (command, batch), (code, stdout, log, _) in zip(jobs, results):
        lines = OUTCOME.findall(stdout)
        reported = {name: outcome for name, outcome, _ in lines}
        timings += [(float(seconds), name) for name, _, seconds in lines if seconds]
        if not batch:
            # The doc tests: libtest's own count is the whole check.
            passed = sum(outcome == "ok" for outcome in reported.values())
            if code != 0 or passed == 0:
                failed = True
                print(f"FAIL doc tests: {passed} passed", flush=True)
                print(log, file=sys.stderr)
            else:
                print(f"ok   doc tests: {passed} passed")
            continue
        for test in batch:
            outcomes[test] = reported.get(test[1], "not run")
        if code != 0:
            print(log, file=sys.stderr)
    for label, chosen in groups.items():
        here = [test for test in chosen if test in outcomes]
        if not here:
            continue
        broken = [name for selection, name in here if outcomes[(selection, name)] != "ok"]
        passed = len(here) - len(broken)
        if broken:
            failed = True
            print(f"FAIL {label}: {passed} passed, {len(broken)} failed: {', '.join(broken)}")
        else:
            print(f"ok   {label}: {passed} passed")
    print(f"shard {index}/{count}: {len(mine)} tests in {len(jobs)} processes, "
          f"{time.monotonic() - start:.0f}s; slowest processes:")
    for (command, batch), (_, _, _, took) in sorted(
            zip(jobs, results), key=lambda pair: -pair[1][3])[:5]:
        print(f"  {took:5.0f}s {', '.join(name for _, name in batch) or 'doc tests'}")
    print("slowest tests, by libtest's clock:")
    for seconds, name in sorted(timings, reverse=True)[:args.slowest]:
        print(f"  {seconds:7.1f}s {name}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
