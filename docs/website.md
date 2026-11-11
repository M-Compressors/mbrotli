# Documentation website

The [mbrotli book](https://m-compressors.github.io/mbrotli/) is built with
[mdBook](https://rust-lang.github.io/mdBook/) and published through GitHub Pages.
All pages in `docs/` and `architecture/` are included, along with their charts,
CSV measurements, and environment records. Edit those files directly: there is
no second maintained copy of the documentation.

## Build locally

Requires Python **3.10+** and the pinned book tools:

```sh
cargo install mdbook --version 0.5.4 --locked
cargo install mdbook-mermaid --version 0.17.1 --locked
python3 scripts/docs.py build
```

Open `target/book/index.html`, or serve the book with:

```sh
python3 scripts/docs.py serve
```

The server listens on `http://127.0.0.1:3000`. Stop and rerun it after editing
source Markdown: the server watches the generated source tree rather than the
canonical directories. No Node.js installation or runtime CDN is needed.
Mermaid assets come from the pinned preprocessor and are served with the book.

## How source files become pages

`scripts/docs.py` copies `docs/` and `architecture/` into ignored
`target/book-src/`, creates a table of contents, extracts Mermaid's bundled
JavaScript into `target/book-assets/`, then invokes `mdbook build` using the root
`book.toml`. The output goes to `target/book/`. In the staged copy, README pages
are renamed to `index.md` and the introductory page becomes the root `index.md`;
their links are rewritten to match.

Getting started, recipes, and benchmarks have curated navigation. Architecture
entries follow the tables in `architecture/README.md`. Every source Markdown
file must appear in the table of contents: a missing architecture entry fails
preparation. New guide pages are included automatically at the end of the guide
navigation until they receive a curated position.

Relative links between published pages stay local. Links to source files outside
the published directories point to GitHub's `master` branch. Code fences are
preserved. The staged index pages become `index.html` pages. The build checks
local files **and heading anchors** after rendering,
including HTML links, images, and downloaded benchmark data.

## Check the examples

```sh
python3 scripts/docs.py test-examples
```

This compiles and runs each Rust program in getting started, parallel, frames,
Sans I/O compression/decompression, and the I/O guide against the local crate
with std and experimental features, plus
Rayon. Each program checks its decoded result. Temporary consumer source and
build products remain under `target/book-examples/`.

## Publish with GitHub Pages

In the repository settings, select **Pages → Build and deployment → Source →
GitHub Actions** once. `.github/workflows/pages.yml` then:

1. Builds and validates the book on pull requests and pushes to `master`.
2. Compiles and runs the documented recipes.
3. Uploads the static book as a Pages artifact.
4. Deploys only on `master` pushes or a manual run on `master`.

Pull requests validate without publishing or receiving Pages write permissions.
Deployment uses the `github-pages` environment and GitHub's Pages actions;
there is no generated-content branch. The site lives under `/mbrotli/`, and
relative asset links support that prefix and local previews.

See [documentation architecture](../architecture/documentation.md) for the
source/build boundaries and the [CI specification](../architecture/ci.md).
