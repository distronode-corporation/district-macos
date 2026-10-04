#!/usr/bin/env python3
"""Add one release to the Developer ID build's Sparkle appcast.

    python3 scripts/appcast.py --feed appcast.xml --version 1.0 --build 20024 \\
        --url https://github.com/.../releases/download/v1.0/DistrictAI-1.0-20024.dmg \\
        --length 32389113 --signature <base64> --minimum-system-version 14.0 \\
        --release-notes-url https://github.com/.../releases/tag/v1.0

Called by scripts/release-publish.sh, which reads every value from the release's own
files (the .dmg, its .sig, project.yml) after checking them. Rewrites `--feed` in place
and prints `added` or `unchanged`.

The feed lives in distronode-corporation/updates (`district/macos/appcast.xml`), served
at the `SUFeedURL` in project.yml. One `<item>` per release, newest first; earlier items
are kept, so a copy that skipped a release still finds the newest one.

⛔ AN ITEM IS NEVER REWRITTEN. Sparkle orders releases by `sparkle:version` (the build
number), and an installed copy may already have fetched an item, so:
  - a build already in the feed with the same download, size and signature is left
    alone (`unchanged`: a publish run re-run after its push failed);
  - a build already in the feed with anything different is refused;
  - a build at or below the newest one in the feed is refused, because Sparkle would
    never offer it.

Standard library only, so it runs on any runner without an install step.
"""

from __future__ import annotations

import argparse
import email.utils
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
S = f"{{{SPARKLE}}}"
# Sparkle's own content type for a download in `generate_appcast` output.
ENCLOSURE_TYPE = "application/octet-stream"

ET.register_namespace("sparkle", SPARKLE)


class AppcastError(Exception):
    pass


def _check_inputs(args: argparse.Namespace) -> None:
    if not re.fullmatch(r"\d+(\.\d+){1,2}", args.version):
        raise AppcastError(f"version '{args.version}' is not a version number.")
    if not re.fullmatch(r"\d+", args.build):
        raise AppcastError(f"build '{args.build}' is not a build number.")
    if not re.fullmatch(r"https://github\.com/[^\s\"<>]+/releases/download/v[^\s\"<>/]+/[^\s\"<>/]+\.dmg", args.url):
        raise AppcastError(f"url '{args.url}' is not a .dmg on a GitHub Release.")
    if not re.fullmatch(r"[1-9]\d*", args.length):
        raise AppcastError(f"length '{args.length}' is not a size in bytes.")
    if not re.fullmatch(r"[A-Za-z0-9+/]{86}==", args.signature):
        raise AppcastError("the signature is not one base64 Ed25519 signature.")
    if not re.fullmatch(r"\d+(\.\d+){1,2}", args.minimum_system_version):
        raise AppcastError(f"minimum system version '{args.minimum_system_version}' is not a version number.")
    if not args.release_notes_url.startswith("https://"):
        raise AppcastError(f"release notes url '{args.release_notes_url}' is not https.")


def _item(args: argparse.Namespace, pub_date: str) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.version}"
    ET.SubElement(item, "pubDate").text = pub_date
    ET.SubElement(item, f"{S}version").text = args.build
    ET.SubElement(item, f"{S}shortVersionString").text = args.version
    ET.SubElement(item, f"{S}minimumSystemVersion").text = args.minimum_system_version
    ET.SubElement(item, f"{S}fullReleaseNotesLink").text = args.release_notes_url
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": args.url,
            "length": args.length,
            "type": ENCLOSURE_TYPE,
            f"{S}edSignature": args.signature,
        },
    )
    return item


def _fingerprint(item: ET.Element) -> tuple[str, ...]:
    """What makes two items the same release: everything but the date."""
    enclosure = item.find("enclosure")
    attrs = enclosure.attrib if enclosure is not None else {}
    return (
        (item.findtext(f"{S}version") or "").strip(),
        (item.findtext(f"{S}shortVersionString") or "").strip(),
        (item.findtext(f"{S}minimumSystemVersion") or "").strip(),
        attrs.get("url", ""),
        attrs.get("length", ""),
        attrs.get(f"{S}edSignature", ""),
    )


def add(feed: Path, args: argparse.Namespace, pub_date: str) -> str:
    """Add the release to the feed file; return 'added' or 'unchanged'."""
    _check_inputs(args)
    try:
        tree = ET.parse(feed)
    except (OSError, ET.ParseError) as error:
        raise AppcastError(f"cannot read the feed {feed}: {error}") from error
    root = tree.getroot()
    channel = root.find("channel")
    if root.tag != "rss" or channel is None:
        raise AppcastError(f"{feed} is not an RSS feed with a channel.")
    new = _item(args, pub_date)
    items = channel.findall("item")
    builds: list[int] = []
    for existing in items:
        build = (existing.findtext(f"{S}version") or "").strip()
        if not build.isdigit():
            raise AppcastError(f"{feed} has an item whose sparkle:version '{build}' is not a build number.")
        if build == args.build:
            if _fingerprint(existing) == _fingerprint(new):
                return "unchanged"
            raise AppcastError(
                f"build {args.build} is already in the feed with a different download, size or signature; "
                "an item an installed copy may have read is never rewritten."
            )
        builds.append(int(build))
    if builds and int(args.build) <= max(builds):
        raise AppcastError(
            f"build {args.build} is not above {max(builds)}, the newest in the feed, so Sparkle would never offer it."
        )
    # Newest first: before the first existing item, after the channel's own fields.
    position = list(channel).index(items[0]) if items else len(channel)
    channel.insert(position, new)
    ET.indent(tree, space="  ")
    tree.write(feed, encoding="utf-8", xml_declaration=True)
    with feed.open("a", encoding="utf-8") as handle:
        handle.write("\n")
    return "added"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--feed", required=True, type=Path)
    parser.add_argument("--version", required=True, help="CFBundleShortVersionString, e.g. 1.0")
    parser.add_argument("--build", required=True, help="CFBundleVersion, e.g. 20024")
    parser.add_argument("--url", required=True, help="the .dmg's GitHub Release download URL")
    parser.add_argument("--length", required=True, help="the .dmg's size in bytes")
    parser.add_argument("--signature", required=True, help="the .dmg's EdDSA signature (the .sig file)")
    parser.add_argument("--minimum-system-version", required=True)
    parser.add_argument("--release-notes-url", required=True)
    parser.add_argument("--pub-date", help="RFC 822 date; defaults to now")
    args = parser.parse_args(argv)
    pub_date = args.pub_date or email.utils.format_datetime(datetime.now(timezone.utc))
    try:
        print(add(args.feed, args, pub_date))
    except AppcastError as error:
        print(f"FATAL - {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
