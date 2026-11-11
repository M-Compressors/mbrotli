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
SITE = "https://m-compressors.github.io/mbrotli/"
RECIPES = [
    "docs/getting-started.md", "docs/configuration.md", "docs/memory.md",
    "docs/decompression.md", "docs/streaming.md", "docs/parallel.md", "docs/frames.md",
    "docs/sans-io-compression.md", "docs/sans-io-decompression.md", "docs/io.md",
]
# Sidebar parts in reading order. A tuple nests its tail under its first page;
# nested chapters stay folded until the reader opens their parent.
GUIDE_PARTS = [
    ("Start here", ["getting-started", "README", "examples/README"]),
    ("Guides", ["configuration", "memory", "decompression",
                ("streaming", "io", "sans-io-compression", "sans-io-decompression"),
                "parallel", "frames", "dictionaries"]),
]
CONTRIBUTING = ["development", "benchmarking", "fuzz-campaigns", "website"]


def run(*command):
    subprocess.run(command, cwd=ROOT, check=True)


def published_path(page):
    if str(page) == "docs/introduction.md":
        return Path("index.md")
    return page.with_name("index.md") if page.name == "README.md" else page


def repository_link(url, page, published_as=None):
    """Keep published links relative; point other files at the source browser.

    `page` is the source file that contains the link. `published_as` overrides
    where its text is staged, for content republished on a generated page.
    """
    parsed = urlsplit(url)
    if parsed.scheme or parsed.netloc or not parsed.path:
        return url
    target = (ROOT / page.parent / unquote(parsed.path)).resolve()
    relative = target.relative_to(ROOT)
    if not target.exists():
        raise ValueError(f"{page}: missing link target {url}")
    if relative.parts[0] in ("docs", "architecture"):
        destination = published_path(relative)
        origin = (published_as or published_path(page)).parent
        path = posixpath.relpath(destination.as_posix(), origin.as_posix())
        return path + ("?" + parsed.query if parsed.query else "") + (
            "#" + parsed.fragment if parsed.fragment else ""
        )
    kind = "tree" if target.is_dir() else "blob"
    suffix = ("?" + parsed.query if parsed.query else "") + (
        "#" + parsed.fragment if parsed.fragment else ""
    )
    return f"{REPOSITORY}/{kind}/master/{relative.as_posix()}{suffix}"


def rewrite_links(markdown, page, published_as=None):
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
                lambda m: m[1] + repository_link(m[2], page, published_as), line,
            )
            line = re.sub(
                r"^(\s{0,3}\[[^\]\n]+\]:\s*)(\S+)",
                lambda m: m[1] + repository_link(m[2], page, published_as), line,
            )
            line = re.sub(
                r'''((?:href|src)=["'])([^"']+)''',
                lambda m: m[1] + repository_link(m[2], page, published_as), line,
            )
        lines.append(line)
    return "".join(lines)


def title(page):
    return re.search(r"^# (.+)$", (ROOT / page).read_text(), re.MULTILINE)[1]


def slug(heading):
    return re.sub(r"[^a-z0-9]+", "-", heading.lower()).strip("-")


def architecture_sections():
    """Yield (heading, body, [(page, label)]) for each indexed section."""
    index = (ROOT / "architecture/README.md").read_text()
    for heading, body in re.findall(r"^## ([^\n]+)\n(.*?)(?=^## |\Z)", index, re.MULTILINE | re.DOTALL):
        entries = re.findall(r"^\| \[([^]]+)\]\(([^)]+\.md)\)", body, re.MULTILINE)
        if entries:
            yield heading, body.strip() + "\n", [(f"architecture/{page}", label) for label, page in entries]


def section_path(heading):
    return Path("architecture/sections") / f"{slug(heading)}.md"


def summary():
    pages = set()
    lines = ["# Summary", ""]

    def chapter(page, label=None, depth=0):
        pages.add(page)
        lines.append(f'{"  " * depth}- [{label or title(page)}]({published_path(Path(page)).as_posix()})')

    def part(name):
        lines.extend(["", f"# {name}", ""])

    chapter("docs/introduction.md", "Overview")
    curated = {f"docs/{page}.md" for page in CONTRIBUTING}
    for _, entries in GUIDE_PARTS:
        for entry in entries:
            curated.update(f"docs/{page}.md" for page in ([entry] if isinstance(entry, str) else entry))
    for name, entries in GUIDE_PARTS:
        part(name)
        for entry in entries:
            parent, *children = [entry] if isinstance(entry, str) else entry
            chapter(f"docs/{parent}.md")
            for child in children:
                chapter(f"docs/{child}.md", depth=1)
        if name == "Guides":
            # New guides are always published, even before they get a curated position.
            for page in sorted((ROOT / "docs").glob("*.md")):
                relative = page.relative_to(ROOT).as_posix()
                if relative not in curated | pages | {"docs/correctness.md"}:
                    chapter(relative)

    part("Performance and correctness")
    chapter("docs/correctness.md")
    chapter("docs/benchmarks/README.md")
    for codec in ["encoders", "decoders"]:
        chapter(f"docs/benchmarks/{codec}/README.md", depth=1)
        for quality in range(12):
            chapter(f"docs/benchmarks/{codec}/q{quality}.md", f"Quality {quality}", 2)
    for page in sorted((ROOT / "docs").rglob("*.md")):
        relative = page.relative_to(ROOT).as_posix()
        if relative not in curated | pages:
            chapter(relative, depth=1)

    part("How it works")
    chapter("architecture/README.md", "Architecture overview")
    for heading, _, specifications in architecture_sections():
        lines.append(f"- [{heading}]({section_path(heading).as_posix()})")
        for page, label in specifications:
            chapter(page, label, 1)

    part("Contributing")
    for page in CONTRIBUTING:
        chapter(f"docs/{page}.md")
    expected = {p.relative_to(ROOT).as_posix() for folder in ["docs", "architecture"]
                for p in (ROOT / folder).rglob("*.md")}
    if expected != pages:
        raise ValueError(f"SUMMARY mismatch: {sorted(expected.symmetric_difference(pages))}")
    return "\n".join(lines) + "\n"


def write_section_pages():
    """Give each architecture group a landing page built from its index table."""
    index = Path("architecture/README.md")
    for heading, body, _ in architecture_sections():
        target = SOURCE / section_path(heading)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            f"# {heading}\n\n{rewrite_links(body, index, section_path(heading))}\n"
            f"[Architecture overview and module map](../index.md)\n"
        )


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
    write_section_pages()
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
    # The root README is not part of the book, but it links into the published site.
    readme = ROOT / "README.md"
    for url in sorted(set(re.findall(re.escape(SITE) + r"[^\s)\]>\"']*", readme.read_text()))):
        parsed = urlsplit(url)
        target = (OUTPUT / unquote(parsed.path.removeprefix(urlsplit(SITE).path))).resolve()
        if target.is_dir():
            target /= "index.html"
        if not target.exists():
            errors.add(f"README.md: missing {url}")
        elif parsed.fragment and unquote(parsed.fragment) not in pages[target].ids:
            errors.add(f"README.md: missing anchor {url}")
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
