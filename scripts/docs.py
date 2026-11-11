#!/usr/bin/env python3
"""Build the mdBook from canonical repository sources; validate links and recipes."""

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import posixpath
import re
import shutil
import subprocess
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "target/book-src"
OUTPUT = ROOT / "target/book"
REPOSITORY = "https://github.com/M-Compressors/mbrotli"
RECIPES = [
    "docs/getting-started.md", "docs/parallel.md", "docs/frames.md",
    "docs/sans-io-compression.md", "docs/sans-io-decompression.md", "docs/io.md",
]


def run(*command):
    subprocess.run(command, cwd=ROOT, check=True)


def published_path(page):
    if str(page) == "docs/introduction.md":
        return Path("index.md")
    return page.with_name("index.md") if page.name == "README.md" else page


def repository_link(url, page):
    """Keep published links relative; point other files at the source browser."""
    parsed = urlsplit(url)
    if parsed.scheme or parsed.netloc or not parsed.path:
        return url
    target = (ROOT / page.parent / unquote(parsed.path)).resolve()
    relative = target.relative_to(ROOT)
    if not target.exists():
        raise ValueError(f"{page}: missing link target {url}")
    if relative.parts[0] in ("docs", "architecture"):
        destination = published_path(relative)
        origin = published_path(page).parent
        path = posixpath.relpath(destination.as_posix(), origin.as_posix())
        return path + ("?" + parsed.query if parsed.query else "") + (
            "#" + parsed.fragment if parsed.fragment else ""
        )
    kind = "tree" if target.is_dir() else "blob"
    suffix = ("?" + parsed.query if parsed.query else "") + (
        "#" + parsed.fragment if parsed.fragment else ""
    )
    return f"{REPOSITORY}/{kind}/master/{relative.as_posix()}{suffix}"


def rewrite_links(markdown, page):
    """Rewrite Markdown/HTML destinations without changing fenced code."""
    lines = []
    fence = None
    for line in markdown.splitlines(keepends=True):
        marker = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker:
            value = marker[1]
            if fence is None:
                fence = value
            elif value[0] == fence[0] and len(value) >= len(fence):
                fence = None
            lines.append(line)
            continue
        if fence is None:
            line = re.sub(
                r"(!?\[[^\]\n]*\]\()([^\s)]+)",
                lambda m: m[1] + repository_link(m[2], page), line,
            )
            line = re.sub(
                r"^(\s{0,3}\[[^\]\n]+\]:\s*)(\S+)",
                lambda m: m[1] + repository_link(m[2], page), line,
            )
            line = re.sub(
                r'''((?:href|src)=["'])([^"']+)''',
                lambda m: m[1] + repository_link(m[2], page), line,
            )
        lines.append(line)
    return "".join(lines)


def title(page):
    return re.search(r"^# (.+)$", (ROOT / page).read_text(), re.MULTILINE)[1]


def summary():
    pages = set()
    lines = ["# Summary", ""]

    def chapter(page, label=None, depth=0):
        pages.add(page)
        lines.append(f'{"  " * depth}- [{label or title(page)}]({published_path(Path(page)).as_posix()})')

    chapter("docs/introduction.md", "Welcome to mbrotli")
    lines.extend(["", "# User guide", ""])
    for page in ["getting-started", "README", "examples/README",
                 "sans-io-compression", "sans-io-decompression", "io", "parallel", "frames",
                 "dictionaries", "correctness"]:
        chapter(f"docs/{page}.md")
    lines.extend(["", "# Benchmarks", ""])
    chapter("docs/benchmarks/README.md")
    for codec in ["encoders", "decoders"]:
        chapter(f"docs/benchmarks/{codec}/README.md")
        for quality in range(12):
            chapter(f"docs/benchmarks/{codec}/q{quality}.md", f"Quality {quality}", 1)
    for page in sorted((ROOT / "docs/benchmarks").glob("*.md")):
        relative = page.relative_to(ROOT).as_posix()
        if relative not in pages:
            chapter(relative)
    lines.extend(["", "# Contributing", ""])
    for page in ["development", "benchmarking", "website"]:
        chapter(f"docs/{page}.md")
    # New guides are always published, even before they get a curated position.
    for page in sorted((ROOT / "docs").rglob("*.md")):
        relative = page.relative_to(ROOT).as_posix()
        if relative not in pages:
            chapter(relative)
    lines.extend(["", "# Architecture", ""])
    chapter("architecture/README.md", "Architecture overview")
    section = None
    for line in (ROOT / "architecture/README.md").read_text().splitlines():
        if line.startswith("## "):
            section = line[3:]
        match = re.match(r"\| \[([^]]+)\]\(([^)]+\.md)\)", line)
        if match:
            if section:
                lines.extend(["", f"# Architecture · {section}", ""])
                section = None
            chapter(f"architecture/{match[2]}", match[1])
    expected = {p.relative_to(ROOT).as_posix() for folder in ["docs", "architecture"]
                for p in (ROOT / folder).rglob("*.md")}
    if expected != pages:
        raise ValueError(f"SUMMARY mismatch: {sorted(expected.symmetric_difference(pages))}")
    return "\n".join(lines) + "\n"


def prepare():
    if SOURCE.exists():
        shutil.rmtree(SOURCE)
    SOURCE.mkdir(parents=True)
    for folder in ["docs", "architecture"]:
        for page in (ROOT / folder).rglob("*"):
            if not page.is_file() or page.name == ".DS_Store":
                continue
            relative = page.relative_to(ROOT)
            target = SOURCE / published_path(relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            if page.suffix == ".md":
                target.write_text(rewrite_links(page.read_text(), relative))
            else:
                shutil.copy2(page, target)
    (SOURCE / "SUMMARY.md").write_text(summary())
    # The preprocessor bundles Mermaid; extract its assets into ignored build
    # storage. No CDN or Node dependency is required, including at read time.
    assets = ROOT / "target/book-assets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "book.toml").write_text('[book]\ntitle = "Mermaid assets"\n')
    run("mdbook-mermaid", "install", str(assets))
    print(f"Prepared {len(list(SOURCE.rglob('*.md'))) - 1} chapters", flush=True)


class Page(HTMLParser):
    def __init__(self, file):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.links = []
        self.feed(file.read_text())

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        if "id" in attributes:
            self.ids.add(attributes["id"])
        for name in ("href", "src"):
            if attributes.get(name):
                self.links.append(attributes[name])


def check_links():
    output = OUTPUT.resolve()
    pages = {p.resolve(): Page(p) for p in OUTPUT.rglob("*.html")}
    if not pages:
        raise ValueError("No built HTML; run python3 scripts/docs.py build first")
    errors = set()
    for file, page in pages.items():
        for url in page.links:
            parsed = urlsplit(url)
            if parsed.scheme or parsed.netloc:
                continue
            if parsed.path.startswith("/mbrotli/"):
                target = OUTPUT / unquote(parsed.path.removeprefix("/mbrotli/"))
            elif parsed.path.startswith("/"):
                target = OUTPUT / unquote(parsed.path.lstrip("/"))
            else:
                target = file.parent / unquote(parsed.path) if parsed.path else file
            target = target.resolve()
            if target.is_dir():
                target /= "index.html"
            if not target.is_relative_to(OUTPUT.resolve()) or not target.exists():
                errors.add(f"{file.relative_to(output)}: missing {url}")
            elif target in pages and parsed.fragment and unquote(parsed.fragment) not in pages[target].ids:
                errors.add(f"{file.relative_to(output)}: missing anchor {url}")
    if errors:
        raise ValueError("\n".join(sorted(errors)))
    print(f"Checked local links and anchors in {len(pages)} HTML pages", flush=True)


def test_examples():
    package = ROOT / "target/book-examples"
    bins = package / "src/bin"
    if bins.exists():
        shutil.rmtree(bins)
    bins.mkdir(parents=True, exist_ok=True)
    (package / "Cargo.toml").write_text(
        '[package]\nname = "mbrotli-book-examples"\nversion = "0.0.0"\n'
        'edition = "2024"\npublish = false\n[workspace]\n[dependencies]\n'
        f'mbrotli = {{ path = {json.dumps(str(ROOT))}, features = ["experimental"] }}\n'
        'rayon = "1.12"\n'
    )
    names = []
    for page in RECIPES:
        blocks = re.findall(r"^```rust\n(.*?)^```", (ROOT / page).read_text(), re.MULTILINE | re.DOTALL)
        for index, block in enumerate(blocks, 1):
            name = f"{Path(page).stem.replace('-', '_')}_{index}"
            (bins / f"{name}.rs").write_text(block)
            names.append(name)
    manifest = str(package / "Cargo.toml")
    run("cargo", "build", "--release", "--manifest-path", manifest, "--bins")
    for name in names:
        run(str(package / "target/release" / name))
    print(f"Compiled and ran {len(names)} documented Rust programs", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "build", "serve", "check-links", "test-examples"])
    args = parser.parse_args()
    if args.command in ("prepare", "build", "serve"):
        prepare()
    if args.command == "build":
        if OUTPUT.exists():
            shutil.rmtree(OUTPUT)
        run("mdbook", "build")
        check_links()
    elif args.command == "serve":
        run("mdbook", "serve", "--hostname", "127.0.0.1")
    elif args.command == "check-links":
        check_links()
    elif args.command == "test-examples":
        test_examples()


if __name__ == "__main__":
    main()
