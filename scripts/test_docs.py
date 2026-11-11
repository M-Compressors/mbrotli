"""Focused checks for source staging, navigation, and link validation."""

from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import docs


class DocumentationTests(unittest.TestCase):
    def test_published_paths_map_indexes_and_landing_page(self):
        self.assertEqual(docs.published_path(Path("docs/README.md")), Path("docs/index.md"))
        self.assertEqual(docs.published_path(Path("docs/introduction.md")), Path("index.md"))
        self.assertEqual(docs.published_path(Path("docs/frames.md")), Path("docs/frames.md"))

    def test_links_keep_published_navigation_relative(self):
        page = Path("docs/introduction.md")
        self.assertEqual(docs.repository_link("README.md#configuration", page),
                         "docs/index.md#configuration")
        self.assertEqual(docs.repository_link("../architecture/README.md", page),
                         "architecture/index.md")
        self.assertEqual(docs.repository_link("benchmarks/encoder-comparison.csv", page),
                         "docs/benchmarks/encoder-comparison.csv")

    def test_source_links_point_at_repository(self):
        self.assertEqual(docs.repository_link("../Cargo.toml", Path("docs/README.md")),
                         f"{docs.REPOSITORY}/blob/master/Cargo.toml")
        self.assertEqual(docs.repository_link("../src/", Path("docs/README.md")),
                         f"{docs.REPOSITORY}/tree/master/src")

    def test_external_urls_and_fragments_are_preserved(self):
        for url in ["https://docs.rs/mbrotli", "#configuration", "mailto:test@example.com"]:
            self.assertEqual(docs.repository_link(url, Path("docs/README.md")), url)

    def test_missing_source_destination_fails(self):
        with self.assertRaisesRegex(ValueError, "missing link target"):
            docs.repository_link("missing-page.md", Path("docs/README.md"))

    def test_code_fences_are_not_rewritten(self):
        source = "```md\n[example](missing-page.md)\n```\n[guide](README.md)\n"
        self.assertEqual(docs.rewrite_links(source, Path("docs/frames.md")),
                         "```md\n[example](missing-page.md)\n```\n[guide](index.md)\n")

    def test_reference_definitions_and_html_links_are_rewritten(self):
        source = '[guide]: README.md#configuration\n<a href="README.md">Guide</a>\n'
        expected = '[guide]: index.md#configuration\n<a href="index.md">Guide</a>\n'
        self.assertEqual(docs.rewrite_links(source, Path("docs/frames.md")), expected)

    def test_summary_covers_the_repository(self):
        summary = docs.summary()
        self.assertIn("[Getting started](docs/getting-started.md)", summary)
        self.assertIn("[Documentation publishing](architecture/documentation.md)", summary)
        self.assertIn("[Quality 11](docs/benchmarks/encoders/q11.md)", summary)
        self.assertNotIn("# Architecture · Module map", summary)

    def test_html_checker_accepts_downloads_fragments_and_pages_prefix(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "index.html").write_text('<a href="/mbrotli/#welcome">Home</a>'
                                               '<h1 id="welcome">Welcome</h1>'
                                               '<a href="measurements.csv">Data</a>')
            (output / "measurements.csv").write_text("quality,size\n5,10\n")
            with patch.object(docs, "OUTPUT", output):
                docs.check_links()

    def test_html_checker_rejects_missing_file_and_anchor(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "index.html").write_text('<a href="#missing">Anchor</a>'
                                               '<img src="absent.svg">')
            with patch.object(docs, "OUTPUT", output):
                with self.assertRaises(ValueError) as caught:
                    docs.check_links()
            self.assertIn("missing anchor #missing", str(caught.exception))
            self.assertIn("missing absent.svg", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
