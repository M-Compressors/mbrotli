#!/usr/bin/env python3
"""Translate the formally verified Rust items into Lean 4 with Charon and Aeneas.

    scripts/extract_lean.py            regenerate verification/lean/Mbrotli/Code/
    scripts/extract_lean.py --check    fail if the committed translation is stale

The proofs in `verification/lean` are about the generated `Code/Types.lean` and
`Code/Funs.lean`, so they must be regenerated whenever one of the items in
`START` (or anything they call) changes; `--check` is what keeps the two from
drifting apart. Standard-library items the Aeneas library has no model for are
written by hand in `Code/FunsExternal.lean`; `EXTERNALS` lists them, and any
other unmodelled item fails the run. Source line
ranges are stripped from the translation, so moving code around without
changing it leaves the file as it is.

Charon and Aeneas come from the pinned Aeneas release `AENEAS_RELEASE`, which
bundles both and names the nightly Rust toolchain Charon is built against.
The bundle is downloaded once into `target/aeneas/` and the toolchain is
installed with rustup when it is missing. Charon compiles the crate into its
own `target/charon/` so the nightly build never touches the ordinary one.
"""
from pathlib import Path
import argparse
import filecmp
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

root = Path(__file__).resolve().parents[1]

# The Aeneas release whose Charon, Aeneas and Lean library are used. The Lean
# side pins the same commit in `verification/lean/lakefile.lean`.
AENEAS_RELEASE = "nightly-2026.10.24-74aabd5"

# Items translated together with everything they refer to. Paths use Charon's
# name-matcher syntax; `_` stands for an inherent `impl` block.
START = [
    "crate::shared::command",
    "crate::shared::format::INS_BASE",
    "crate::shared::format::INS_EXTRA",
    "crate::shared::format::COPY_BASE",
    "crate::shared::format::COPY_EXTRA",
    "crate::decompressor::core::stream::commands",
    "crate::shared::distance",
    "crate::decompressor::core::distance",
]

# Items of the modules above that are left out: they allocate or are
# SIMD-generic, which Aeneas has no model for or cannot translate at all.
EXCLUDE = [
    f"crate::decompressor::core::distance::_::{method}" for method in ("table", "fill_table")
] + [
    # The command-extension search is SIMD-generic, which Aeneas cannot model.
    "crate::shared::command::extend_last_command",
    "crate::shared::command::extend_into_prefix",
    "crate::shared::command::CommandExtension",
]

# Standard-library items modelled by hand in `Code/FunsExternal.lean`.
EXTERNALS = {
    "U64.Insts.CoreConvertTryFromU128TryFromIntError.try_from",
    "core.num.U64.checked_add_signed",
    "core.option.Option.ok_or_else",
    "core.option.Option.filter",
}

OUTPUT = root / "verification" / "lean" / "Mbrotli" / "Code"
GENERATED = ("Types.lean", "Funs.lean")


def asset() -> str:
    system = {"Darwin": "macos", "Linux": "linux"}.get(platform.system())
    machine = {"arm64": "aarch64", "aarch64": "aarch64", "x86_64": "x86_64"}.get(platform.machine())
    if system is None or machine is None:
        sys.exit(f"no Aeneas build for {platform.system()} {platform.machine()}")
    return f"aeneas-{system}-{machine}.tar.gz"


def bundle() -> Path:
    """Returns the unpacked release, downloading it on first use."""
    directory = root / "target" / "aeneas" / AENEAS_RELEASE
    if (directory / "aeneas").exists():
        return directory
    url = f"https://github.com/AeneasVerif/aeneas/releases/download/{AENEAS_RELEASE}/{asset()}"
    print(f"downloading {url}", file=sys.stderr)
    partial = directory.with_name(directory.name + ".partial")
    shutil.rmtree(partial, ignore_errors=True)
    partial.mkdir(parents=True)
    archive = partial / asset()
    with urllib.request.urlopen(url) as response, archive.open("wb") as out:
        shutil.copyfileobj(response, out)
    subprocess.run(["tar", "-xzf", archive.name], check=True, cwd=partial)
    archive.unlink()
    partial.rename(directory)
    return directory


def ensure_toolchain(tools: Path) -> None:
    """Installs the nightly toolchain the bundled Charon was built against."""
    pins = (tools / "rust-toolchain").read_text()
    channel = re.search(r'^channel\s*=\s*"([^"]+)"', pins, re.M).group(1)
    components = re.search(r'^components\s*=\s*\[([^\]]*)\]', pins, re.M)
    components = re.findall(r'"([^"]+)"', components.group(1)) if components else []
    installed = subprocess.run(
        ["rustup", "toolchain", "list"], check=True, capture_output=True, text=True
    ).stdout
    if not any(line.startswith(channel + "-") for line in installed.splitlines()):
        subprocess.run(
            ["rustup", "toolchain", "install", channel, "--profile", "minimal",
             "-c", ",".join(components)],
            check=True,
        )


def extract(tools: Path, destination: Path) -> None:
    """Writes the Lean translation of `START` into the directory `destination`."""
    with tempfile.TemporaryDirectory() as scratch:
        llbc = Path(scratch) / "mbrotli.llbc"
        command = [str(tools / "charon"), "cargo", "--preset", "aeneas", "--dest-file", str(llbc)]
        for item in START:
            command += ["--start-from", item]
        for item in EXCLUDE:
            command += ["--exclude", item]
        env = dict(os.environ, CARGO_TARGET_DIR=str(root / "target" / "charon"))
        subprocess.run(command, check=True, cwd=root, env=env)

        lean = Path(scratch) / "lean"
        subprocess.run(
            [str(tools / "aeneas"), "-backend", "lean", "-loops-to-rec", "-split-files",
             "-abort-on-error", "-no-progress-bar", "-dest", str(lean), "-subdir", "Mbrotli/Code",
             str(llbc)],
            check=True,
        )
        generated = lean / "Mbrotli" / "Code"
        template = generated / "FunsExternal_Template.lean"
        needed = set(re.findall(r"^axiom (\S+)", template.read_text(), re.M)) if template.exists() else set()
        if needed != EXTERNALS:
            sys.exit("the translation's unmodelled standard-library items changed: "
                     f"new {sorted(needed - EXTERNALS)}, gone {sorted(EXTERNALS - needed)}; "
                     "model them in Code/FunsExternal.lean and update EXTERNALS")
        destination.mkdir(parents=True, exist_ok=True)
        for name in GENERATED:
            text = (generated / name).read_text()
            if "\naxiom " in text:
                sys.exit(f"{name} declares an axiom")
            # Keep the source file of each item but drop its line range, so that
            # an edit elsewhere in the file does not make the translation stale.
            text = re.sub(r", lines \d+:\d+-\d+:\d+", "", text)
            (destination / name).write_text(text)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="compare against the committed translation instead of writing it")
    args = parser.parse_args()

    tools = bundle()
    ensure_toolchain(tools)
    if not args.check:
        extract(tools, OUTPUT)
        return
    with tempfile.TemporaryDirectory() as scratch:
        fresh = Path(scratch)
        extract(tools, fresh)
        for name in GENERATED:
            if not (OUTPUT / name).exists() or not filecmp.cmp(fresh / name, OUTPUT / name, shallow=False):
                sys.exit(f"{(OUTPUT / name).relative_to(root)} is stale; run scripts/extract_lean.py")


if __name__ == "__main__":
    main()
