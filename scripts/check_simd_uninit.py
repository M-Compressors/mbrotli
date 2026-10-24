#!/usr/bin/env python3
"""Run the SIMD and uninitialized-memory tests under Miri or AddressSanitizer.

Tests are chosen by name prefix from the binary's own `--list`, then run with
`--exact`, so a prefix cannot also match an unrelated module by substring, and
a prefix that selects no test, or whose every test is ignored, fails the run
instead of passing silently.

    scripts/check_simd_uninit.py miri [--target TRIPLE] [--jobs N]
    scripts/check_simd_uninit.py asan [--target TRIPLE] [--jobs N]

Miri reaches only the SIMD levels the build enables at compile time; set
`RUSTFLAGS=-Ctarget-cpu=...` (and a separate `CARGO_TARGET_DIR`) to select
them. AddressSanitizer runs natively and reaches every level the host detects.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
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

RESULT = re.compile(r"test result: \w+\. (\d+) passed; (\d+) failed; (\d+) ignored")


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
    else:
        for name in ["RUSTFLAGS", "RUSTDOCFLAGS"]:
            flags = env.get(name, "")
            if "-Zsanitizer=address" not in flags:
                env[name] = f"{flags} -Zsanitizer=address".strip()
    return env


def listed(tool: str, target: str, env: dict[str, str], selection: list[str]) -> list[str]:
    output = subprocess.run(
        cargo(tool, target, selection) + ["--", "--list", "--format", "terse"],
        cwd=root, env=env, capture_output=True, text=True,
    )
    if output.returncode != 0:
        sys.exit(f"listing {' '.join(selection)} failed:\n{output.stderr}")
    return [line.removesuffix(": test") for line in output.stdout.splitlines()
            if line.endswith(": test")]


def run(command: list[str], env: dict[str, str]) -> tuple[bool, int, str, float]:
    """Runs one test command; returns success, the number passed, its log and
    its wall time in seconds."""
    start = time.monotonic()
    output = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True)
    log = output.stdout + output.stderr
    passed = sum(int(found[0]) for found in RESULT.findall(log))
    return output.returncode == 0, passed, log, time.monotonic() - start


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("tool", choices=["miri", "asan"])
    parser.add_argument("--target", default=host())
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    args = parser.parse_args()
    env = environment(args.tool)

    build = cargo(args.tool, args.target, ["--lib", "--no-run"])
    tests = TESTS[args.tool]
    build += [arg for name in sorted({binary for binary, _ in tests}) for arg in ["--test", name]]
    subprocess.run(build, cwd=root, env=env, check=True)

    # One process per test, so tests of one module run in parallel.
    groups: dict[str, list[list[str]]] = {}
    lib = listed(args.tool, args.target, env, ["--lib"])
    for prefix in LIB:
        groups[prefix] = [cargo(args.tool, args.target, ["--lib", "--", "--exact", name])
                          for name in lib if name.startswith(prefix)]
    for binary, prefix in tests:
        names = listed(args.tool, args.target, env, ["--test", binary])
        groups[f"{binary}::{prefix}"] = [
            cargo(args.tool, args.target, ["--test", binary, "--", "--exact", name])
            for name in names if name.startswith(prefix)
        ]
    skips = MIRI_AARCH64_DOC_SKIPS if args.tool == "miri" and args.target.startswith("aarch64") else []
    groups["doc tests"] = [cargo(args.tool, args.target, [
        "--doc", "--", DOC, *[arg for skip in skips for arg in ["--skip", skip]]
    ])]
    empty = [label for label, commands in groups.items() if not commands]
    if empty:
        sys.exit(f"no test matches: {', '.join(empty)}")

    jobs = [(label, command) for label, commands in groups.items() for command in commands]
    with ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda job: run(job[1], env), jobs))
    failed = False
    for label in groups:
        outcomes = [(command, *result) for (owner, command), result in zip(jobs, results)
                    if owner == label]
        passed = sum(count for _, _, count, _, _ in outcomes)
        broken = [log for _, ok, _, log, _ in outcomes if not ok]
        slowest, seconds = max(((command[-1], took) for command, *_, took in outcomes),
                               key=lambda pair: pair[1])
        timing = f"slowest {seconds:.0f}s ({slowest})"
        if broken or passed == 0:
            failed = True
            print(f"FAIL {label}: {passed} passed, {len(broken)} failed; {timing}")
            for log in broken:
                print(log, file=sys.stderr)
        else:
            print(f"ok   {label}: {passed} passed; {timing}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
