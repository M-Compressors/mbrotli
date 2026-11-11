# Documentation publishing

The repository publishes a static **mdBook** through GitHub Pages. The book
contains every Markdown page and associated asset in `docs/` and `architecture/`.
These directories remain the canonical sources; generated book sources, Mermaid
assets, consumer examples, and HTML are local artifacts under ignored `target/`.

## Modules and ownership

```mermaid
graph TD
    Guides[docs: user guides, examples, benchmark data] --> Prepare[scripts/docs.py: prepare]
    Specs[architecture: specifications and index] --> Prepare
    Index[architecture/README.md: architecture navigation and section pages] --> Prepare
    Prepare --> Source[target/book-src: generated Markdown and assets]
    Mermaid[mdbook-mermaid 0.17.1: bundled JS] --> Assets[target/book-assets]
    Config[book.toml, book-theme/custom.css and diagram-zoom.js] --> Build[mdbook 0.5.4]
    Source --> Build
    Assets --> Build
    Build --> HTML[target/book: static HTML and search]
    HTML --> Check[Python local-link and anchor validation]
    Check --> Pages[GitHub Pages artifact]
```

The root `book.toml` owns renderer, theme, search, folding, output path, and
Mermaid preprocessor settings. `book-theme/custom.css` overrides the palette of
mdBook's `light` and `navy` themes and styles tables, the sidebar and the
landing page. `book-theme/diagram-zoom.js` moves a rendered Mermaid SVG into a
modal dialog at its natural size and returns it to its page position on close;
it borrows the node because Mermaid scopes diagram styles by the SVG's id. Search, keyboard navigation,
theme selection, Rust syntax highlighting, and code copying come from mdBook.
Rust playground execution is disabled because its environment lacks mbrotli.

`scripts/docs.py` has five repository-local entry points:

| Command | Behavior |
| --- | --- |
| `prepare` | Recreate the staged source tree, navigation, and bundled diagram assets |
| `build` | Prepare, build HTML, then check local links and heading anchors |
| `serve` | Prepare, then serve the generated tree on loopback port 3000 |
| `check-links` | Validate a previously built HTML tree |
| `test-examples` | Compile and run Rust recipes in a separate Cargo consumer |

## Source and link flow

```mermaid
flowchart TD
    Copy[Copy docs and architecture] --> Links[Inspect destinations outside fenced code]
    Links --> Local{Target in published directories?}
    Local -->|yes| Relative[Keep relative link]
    Local -->|no| GitHub[Link to source on GitHub master]
    Relative --> Summary[Generate SUMMARY with every Markdown page and the section pages]
    GitHub --> Summary
    Summary --> Complete{All source pages indexed?}
    Complete -->|no| Fail[Fail preparation]
    Complete -->|yes| Render[mdBook preprocessors and HTML renderer]
    Render --> Validate[Validate href and src paths, HTML IDs and README site URLs]
    Validate --> Artifact[Publishable static directory]
```

The generated `SUMMARY.md` has five parts: **Start here** (getting started,
the API chooser in `docs/README.md`, examples), **Guides**, **Performance and
correctness**, **How it works**, and **Contributing**. `GUIDE_PARTS` and
`CONTRIBUTING` in `scripts/docs.py` hold the curated order; a tuple nests its
tail under its first page, as the I/O and Sans I/O guides nest under streaming.
Benchmark quality pages nest two levels below the results index. `book.toml`
folds every nested level, so the sidebar opens with top-level chapters only and
mdBook expands the branch of the current page.

Architecture chapters follow the section headings and specification tables in
`architecture/README.md`. For each `##` section that contains a specification
table, preparation writes a generated landing page
`architecture/sections/<slug>.md` holding that section's text, with links
rewritten for its location, and nests the section's specifications under it.
These are the only published pages without a canonical source file. Unindexed
architecture Markdown fails preparation. New guide pages are appended to
**Guides** automatically. No source guide or specification is excluded merely
because it has no manually configured navigation entry.

Preparation preserves fenced code. Relative links to files outside the published
directories are checked for existence and rewritten to GitHub `blob` or `tree`
URLs. Staging maps README pages to `index.md` and the introduction to the root
`index.md`, adjusting relative links and summary entries to their final locations.
CSV, JSON, and SVG assets retain their source directory layout. All generated
HTML local destinations and fragments are checked after rendering. The root
`README.md` is not published, but it links into the site: the same check
resolves each of its `https://m-compressors.github.io/mbrotli/` URLs, with its
fragment, against the built HTML.

The preprocessor's `install` command writes bundled Mermaid assets into a small
generated book under `target/book-assets/`; the real book references those files.
The site needs no runtime CDN, Node package manager, or application server.

## Navigation

```mermaid
graph LR
    Book[SUMMARY.md] --> Overview[Overview: docs/introduction.md]
    Book --> Start[Start here]
    Book --> Guides[Guides]
    Book --> Evidence[Performance and correctness]
    Book --> Internals[How it works]
    Book --> Contributing[Contributing]
    Start --> StartPages[getting started, API chooser, examples]
    Guides --> GuidePages[configuration, memory, decompression, streaming, parallel, frames, dictionaries]
    GuidePages --> Nested[folded: I/O and Sans I/O under streaming]
    Evidence --> Bench[correctness, benchmark index]
    Bench --> Quality[folded: codec indexes, quality pages, run reports]
    Internals --> Sections[overview, generated section pages]
    Sections --> Specs[folded: specifications from architecture/README.md tables]
    Contributing --> Dev[development, benchmarking, fuzz campaigns, website]
```

## Examples and deployment

```mermaid
sequenceDiagram
    participant Source as Markdown recipes
    participant Consumer as Temporary Cargo consumer
    participant CI as Pages build job
    participant Deploy as Pages deploy job
    Source->>Consumer: Extract every rust fence from the recipe guides
    Consumer->>Consumer: Release build with local mbrotli + experimental + Rayon
    Consumer->>CI: Run programs and round-trip assertions
    CI->>CI: Build book and check local links and anchors
    CI->>Deploy: Upload static Pages artifact
    alt master push or manual run on master
        Deploy->>Deploy: Configure Pages and deploy with OIDC
    else pull request
        Deploy->>Deploy: Skip publication
    end
```

Recipes in the guides listed in `RECIPES` (getting started, configuration,
buffers, decompression, streaming, parallel, frames, Sans I/O
compression/decompression, and the I/O guide) are complete Rust programs. `test-examples` generates a separate package beneath
`target/book-examples/`, enables default std codecs plus `experimental`, and adds
Rayon. It runs each binary and propagates build or assertion failures. It does
not change the workspace, public codec APIs, state machines, SIMD dispatch, or
error propagation; normal codec tests remain separate.

`.github/workflows/pages.yml` runs source and recipe checks on matching pull
requests, `master` pushes, and manual dispatch. Only its deployment job has
`pages: write` and `id-token: write`; pull requests cannot deploy. The
`github-pages` environment records the deployed URL. Deployment is serialized
and the output is hosted at `https://m-compressors.github.io/mbrotli/`.

## Known gaps

- The Pages source setting must be configured to **GitHub Actions** in repository
  settings before the first deployment. Adding a workflow alone does not enable it.
- `serve` watches generated files. Restart the command after editing canonical
  sources so preparation runs again.
- The checker validates local destinations and anchors, not external network
  URLs or Mermaid syntax. Browser QA is needed for rendered diagrams.
- The diagram dialog and theme have no automated test; they were checked in a
  desktop browser in the light and navy themes.
- Recipe validation covers the guides in `RECIPES`, not every historical code
  fragment in the implementation specifications.
