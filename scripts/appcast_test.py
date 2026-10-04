#!/usr/bin/env python3
"""Tests for appcast.py that need no network.

    python3 scripts/appcast_test.py
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import appcast  # noqa: E402

S = appcast.S

# The empty feed distronode-corporation/updates was created with, byte for byte.
EMPTY_FEED = """<?xml version='1.0' encoding='utf-8'?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>District AI for macOS</title>
    <link>https://updates.distronode.com/district/macos/appcast.xml</link>
    <description>Updates to the direct download of District AI for macOS. Written by the release workflow of distronode-corporation/district-macos; do not edit by hand.</description>
    <language>en</language>
  </channel>
</rss>
"""

SIG_A = "Z3WG++DpDBpJFzBPyaFty4bD+QAJOOw3Atz9vWgXb4q59gMX+5D7pFXnmpg+sDs5qefO6SWSqeUefGJScOwHAQ=="
SIG_B = "A" * 86 + "=="
REPO = "https://github.com/distronode-corporation/district-macos"
DATE = "Sun, 04 Oct 2026 19:00:00 +0000"


def _args(version: str = "1.0", build: str = "20024", **overrides: str) -> list[str]:
    values = {
        "--version": version,
        "--build": build,
        "--url": f"{REPO}/releases/download/v{version}/DistrictAI-{version}-{build}.dmg",
        "--length": "32389113",
        "--signature": SIG_A,
        "--minimum-system-version": "14.0",
        "--release-notes-url": f"{REPO}/releases/tag/v{version}",
        "--pub-date": DATE,
    }
    values.update({f"--{k.replace('_', '-')}": v for k, v in overrides.items()})
    out: list[str] = []
    for key, value in values.items():
        out += [key, value]
    return out


class AppcastTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.feed = Path(self.tmp.name) / "appcast.xml"
        self.feed.write_text(EMPTY_FEED)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_main(self, argv: list[str]) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = appcast.main(["--feed", str(self.feed), *argv])
        return code, out.getvalue(), err.getvalue()

    def items(self) -> list[ET.Element]:
        return ET.parse(self.feed).getroot().findall("channel/item")

    def test_first_item_carries_every_field_sparkle_reads(self) -> None:
        code, out, _ = self.run_main(_args())
        self.assertEqual((code, out.strip()), (0, "added"))
        (item,) = self.items()
        self.assertEqual(item.findtext("title"), "Version 1.0")
        self.assertEqual(item.findtext("pubDate"), DATE)
        self.assertEqual(item.findtext(f"{S}version"), "20024")
        self.assertEqual(item.findtext(f"{S}shortVersionString"), "1.0")
        self.assertEqual(item.findtext(f"{S}minimumSystemVersion"), "14.0")
        self.assertEqual(item.findtext(f"{S}fullReleaseNotesLink"), f"{REPO}/releases/tag/v1.0")
        enclosure = item.find("enclosure")
        assert enclosure is not None
        self.assertEqual(enclosure.get("url"), f"{REPO}/releases/download/v1.0/DistrictAI-1.0-20024.dmg")
        self.assertEqual(enclosure.get("length"), "32389113")
        self.assertEqual(enclosure.get("type"), "application/octet-stream")
        self.assertEqual(enclosure.get(f"{S}edSignature"), SIG_A)

    def test_channel_fields_and_prefix_are_kept(self) -> None:
        self.run_main(_args())
        text = self.feed.read_text()
        self.assertTrue(text.startswith("<?xml version='1.0' encoding='utf-8'?>\n<rss xmlns:sparkle="))
        self.assertTrue(text.endswith("</rss>\n"))
        self.assertIn("<sparkle:version>20024</sparkle:version>", text)
        self.assertNotIn("ns0:", text)
        channel = ET.parse(self.feed).getroot().find("channel")
        assert channel is not None
        self.assertEqual(channel.findtext("title"), "District AI for macOS")
        self.assertEqual(channel.findtext("language"), "en")
        # The item comes after the channel's own fields.
        self.assertEqual([child.tag for child in channel][-1], "item")

    def test_later_release_goes_first_and_earlier_items_are_kept(self) -> None:
        self.run_main(_args())
        code, out, _ = self.run_main(_args(version="1.1", build="20031", signature=SIG_B))
        self.assertEqual((code, out.strip()), (0, "added"))
        self.assertEqual([i.findtext(f"{S}version") for i in self.items()], ["20031", "20024"])

    def test_the_same_release_again_is_unchanged_whatever_the_date(self) -> None:
        self.run_main(_args())
        before = self.feed.read_bytes()
        code, out, _ = self.run_main(_args(pub_date="Mon, 05 Oct 2026 08:00:00 +0000"))
        self.assertEqual((code, out.strip()), (0, "unchanged"))
        self.assertEqual(self.feed.read_bytes(), before)

    def test_the_same_build_with_another_signature_is_refused(self) -> None:
        self.run_main(_args())
        before = self.feed.read_bytes()
        code, _, err = self.run_main(_args(signature=SIG_B))
        self.assertEqual(code, 1)
        self.assertIn("never rewritten", err)
        self.assertEqual(self.feed.read_bytes(), before)

    def test_an_older_build_is_refused(self) -> None:
        self.run_main(_args(version="1.1", build="20031"))
        code, _, err = self.run_main(_args())
        self.assertEqual(code, 1)
        self.assertIn("not above 20031", err)
        self.assertEqual(len(self.items()), 1)

    def test_hostile_inputs_are_refused_and_nothing_is_written(self) -> None:
        cases = {
            "version": {"version": "1.0<x>"},
            "build": {"build": "20024a"},
            "url": {"url": "https://example.com/DistrictAI.dmg"},
            "url quote": {"url": f'{REPO}/releases/download/v1.0/a".dmg'},
            "length": {"length": "0"},
            "signature": {"signature": "not-a-signature"},
            "minimum": {"minimum_system_version": "fourteen"},
            "notes": {"release_notes_url": "http://example.com"},
        }
        for name, override in cases.items():
            with self.subTest(name):
                code, _, err = self.run_main(_args(**override))
                self.assertEqual(code, 1)
                self.assertIn("FATAL", err)
                self.assertEqual(self.feed.read_text(), EMPTY_FEED)

    def test_a_feed_that_is_not_rss_is_refused(self) -> None:
        self.feed.write_text("<html><body/></html>\n")
        code, _, err = self.run_main(_args())
        self.assertEqual(code, 1)
        self.assertIn("not an RSS feed", err)
        self.feed.write_text("<rss><channel>")
        code, _, err = self.run_main(_args())
        self.assertEqual(code, 1)
        self.assertIn("cannot read the feed", err)

    def test_an_item_without_a_build_number_is_refused(self) -> None:
        self.feed.write_text(EMPTY_FEED.replace("</channel>", "<item><title>x</title></item></channel>"))
        code, _, err = self.run_main(_args())
        self.assertEqual(code, 1)
        self.assertIn("is not a build number", err)


if __name__ == "__main__":
    unittest.main(verbosity=2)
