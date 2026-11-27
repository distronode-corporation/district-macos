#!/usr/bin/env python3
"""Tests for package_pins.py that need no network.

    python3 scripts/package_pins_test.py
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package_pins  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

SPEC = """name: Example
options:
  bundleIdPrefix: com.example

packages:
  # A comment between packages.
  DistrictCore:
    url: https://github.com/distronode-corporation/district-core-swift
    exactVersion: 8.6.0
  swift-asn1:
    url: https://github.com/apple/swift-asn1.git
    exactVersion: "1.7.3"
  Ranged:
    url: https://github.com/example/ranged
    from: 1.0.0
  Elsewhere:
    url: https://example.org/elsewhere
    exactVersion: 2.0.0

targets:
  App:
    type: application
    url: https://github.com/example/not-a-package
    exactVersion: 9.9.9
"""


class ParsePinsTests(unittest.TestCase):
    def test_reads_exact_github_pins_under_packages_only(self):
        pins = package_pins.parse_pins(SPEC)
        self.assertEqual(
            pins,
            [
                package_pins.Pin("DistrictCore", "distronode-corporation", "district-core-swift", "8.6.0"),
                package_pins.Pin("swift-asn1", "apple", "swift-asn1", "1.7.3"),
            ],
        )

    def test_this_repositorys_project_yml_has_pins(self):
        pins = package_pins.parse_pins((ROOT / "project.yml").read_text())
        names = {p.name for p in pins}
        self.assertIn("DistrictCore", names)
        self.assertIn("LiveKit", names)


class VersionTests(unittest.TestCase):
    def test_newer_compares_numerically_and_pads(self):
        self.assertTrue(package_pins.newer("v2.18.0", "2.17.0"))
        self.assertTrue(package_pins.newer("1.10.0", "1.9.9"))
        self.assertTrue(package_pins.newer("150.7871.3", "150.7871.2"))
        self.assertFalse(package_pins.newer("1.2", "1.2.0"))
        self.assertFalse(package_pins.newer("2.17.0", "2.17.0"))
        self.assertFalse(package_pins.newer("2.16.9", "2.17.0"))

    def test_a_pre_release_is_never_newer(self):
        self.assertFalse(package_pins.newer("3.0.0-beta.1", "2.17.0"))
        self.assertFalse(package_pins.newer("release-candidate", "2.17.0"))

    def test_highest_skips_pre_releases_and_non_versions(self):
        self.assertEqual(package_pins.highest(["1.2.0", "1.10.0", "2.0.0-rc1", "latest", "v1.9.0"]), "1.10.0")
        self.assertIsNone(package_pins.highest(["nightly", "2.0.0-beta"]))


class LatestReleaseTests(unittest.TestCase):
    pin = package_pins.Pin("X", "o", "r", "1.0.0")

    def test_uses_the_latest_release_when_it_is_a_version(self):
        with mock.patch.object(package_pins, "gh_json", side_effect=[{"tag_name": "v1.4.0"}]):
            self.assertEqual(package_pins.latest_release(self.pin), "v1.4.0")

    def test_falls_back_to_tags_without_a_release(self):
        with mock.patch.object(package_pins, "gh_json", side_effect=[None, [{"name": "1.2.0"}, {"name": "1.3.0"}]]):
            self.assertEqual(package_pins.latest_release(self.pin), "1.3.0")

    def test_falls_back_to_tags_when_the_release_is_not_a_version(self):
        with mock.patch.object(
            package_pins, "gh_json", side_effect=[{"tag_name": "nightly-2026"}, [{"name": "1.1.0"}]]
        ):
            self.assertEqual(package_pins.latest_release(self.pin), "1.1.0")

    def test_none_when_nothing_is_readable(self):
        with mock.patch.object(package_pins, "gh_json", side_effect=[None, None]):
            self.assertIsNone(package_pins.latest_release(self.pin))


class IssueBodyTests(unittest.TestCase):
    def test_lists_each_update_with_its_releases_page(self):
        pin = package_pins.Pin("LiveKit", "livekit", "client-sdk-swift", "2.17.0")
        body = package_pins.issue_body([(pin, "2.18.0")], [])
        self.assertIn("| LiveKit | 2.17.0 | 2.18.0 | https://github.com/livekit/client-sdk-swift/releases |", body)
        self.assertNotIn("could be read", body)

    def test_names_packages_with_nothing_readable(self):
        pin = package_pins.Pin("LiveKit", "livekit", "client-sdk-swift", "2.17.0")
        other = package_pins.Pin("Sparkle", "sparkle-project", "Sparkle", "2.10.0")
        body = package_pins.issue_body([(pin, "2.18.0")], [other])
        self.assertIn("No release or version tag could be read for: Sparkle.", body)


if __name__ == "__main__":
    unittest.main()
