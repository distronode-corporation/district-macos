#!/usr/bin/env python3
"""Fail on content that must not appear in this public repository.

    python3 scripts/check-public-hygiene.py              # scan the tree
    python3 scripts/check-public-hygiene.py --self-test  # prove each rule works

The scan reads every tracked file plus every untracked file git does not ignore,
so a new file is checked before anyone commits it. Binary files (any NUL byte) are
skipped. Three rules:

    dash    An em dash (U+2014) or an en dash (U+2013), anywhere outside
            contracts/. Use commas, periods or parentheses. A string literal that
            has to hold the character at run time spells it as an escape
            (`"\\u{2014}"` in Swift), which keeps the value and passes the scan.
    host    An internal host name: anything under .internal, .local, .lan,
            .corp or .svc.cluster.local, and the origin-* hosts behind the public
            website (origin-<region> under distronode.com or distronode.ca). Names under
            example.com, example.org, example.net, .test, .example and .invalid
            are reserved for examples (RFC 2606) and are what test data uses.
    gitlab  A GitLab URL or host name. This repository lives on GitHub only.

Files under contracts/ are exempt from `dash` only. This app has no contracts/
directory (its contract fixtures live in district-core-swift), and the exemption is
kept so that the script stays identical in behaviour to that repository's copy.

Copied from distronode-corporation/district-core-swift, which adapted it from
district-linux. Its phone and email rules are not carried over.

`--self-test` plants a violation of each rule, and look-alikes that must NOT trip
one, and fails unless every rule answers as expected. It also builds a throwaway
git repository to prove which files the scan reads. CI runs it before the scan, so
a rule that has stopped matching anything fails loudly instead of passing quietly.

This file spells the two dash characters as escapes and assembles its planted
violations at run time, so that it passes its own scan.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DASHES = {"\u2014": "U+2014 EM DASH", "\u2013": "U+2013 EN DASH"}

# Paths whose dashes are not ours to change (see the module docstring).
DASH_EXEMPT_PREFIXES = ("contracts/",)

# A host name ending in one of the private-use suffixes. Not preceded by a word
# character, a dot or a hyphen, so the match starts at the first label; not
# followed by a word character or a hyphen, so `.internalize` and `.local-x` do
# not match. `.internal` as a Swift enum case (`mode: .internal`) has no label in
# front of the dot and so never matches.
# ⚠️ LOWER CASE ONLY, ON PURPOSE. Host names are case-insensitive, but they are
# written in lower case, and a qualified enum case (`KnowledgeMode.internal`) is
# not: matching case-insensitively would flag every one of them.
INTERNAL_SUFFIX = re.compile(
    r"(?<![\w.\-])((?:[a-z0-9\-]+\.)+(?:svc\.cluster\.local|internal|local|lan|corp))(?![\w\-])",
)

# The origins behind the Cloudflare edge. They are reachable, but a client never
# names one: it talks to the public website, and an origin name in published code
# is an address someone will try to bypass the edge with.
ORIGIN_HOST = re.compile(
    r"(?<![\w.\-])(origin(?:-[a-z0-9]+)*\.distronode\.(?:com|ca))(?![\w\-])",
    re.IGNORECASE,
)

# The SaaS host, or a self-managed host whose first label is the product name, in
# a URL or bare. Lower case only, like INTERNAL_SUFFIX, so a code identifier that
# happens to be spelt the same in another case is not a host name.
GITLAB = re.compile(r"(?<![\w\-])((?:[a-z0-9\-]+\.)*gitlab(?:\.[a-z0-9\-]+)+)(?![\w\-])")


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    column: int
    rule: str
    detail: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}:{self.column}: [{self.rule}] {self.detail}"


def scan_text(text: str, path: str = "<text>") -> list[Finding]:
    findings: list[Finding] = []
    check_dashes = not path.startswith(DASH_EXEMPT_PREFIXES)
    for number, line in enumerate(text.splitlines(), start=1):
        if check_dashes:
            for column, char in enumerate(line, start=1):
                if char in DASHES:
                    findings.append(Finding(path, number, column, "dash", DASHES[char]))
        for pattern in (INTERNAL_SUFFIX, ORIGIN_HOST):
            for m in pattern.finditer(line):
                findings.append(
                    Finding(path, number, m.start(1) + 1, "host", f"{m.group(1)!r} is an internal host name")
                )
        for m in GITLAB.finditer(line):
            findings.append(
                Finding(path, number, m.start(1) + 1, "gitlab", f"{m.group(1)!r} names GitLab")
            )
    return findings


def git_files(root: Path) -> list[str]:
    """Tracked files, plus untracked files that .gitignore does not exclude."""

    def ls(*args: str) -> list[str]:
        out = subprocess.run(
            ["git", "ls-files", "-z", *args],
            cwd=root,
            check=True,
            capture_output=True,
        ).stdout
        return [p for p in out.decode("utf-8").split("\0") if p]

    return sorted(set(ls()) | set(ls("--others", "--exclude-standard")))


def scan_tree(root: Path) -> tuple[int, list[Finding]]:
    scanned = 0
    findings: list[Finding] = []
    for rel in git_files(root):
        path = root / rel
        # A tracked file deleted in the working tree, a submodule, a symlink: none
        # of them is a text file this repository publishes as such.
        if path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        if b"\0" in data:
            continue
        scanned += 1
        findings.extend(scan_text(data.decode("utf-8", errors="replace"), rel))
    return scanned, findings


def self_test() -> int:
    em, en = "\u2014", "\u2013"
    lab = "git" + "lab"
    internal = "." + "internal"

    # Everything here is allowed, including the look-alikes each rule has to leave
    # alone. Allowed content may be written literally; it passes the scan too.
    clean = "\n".join(
        [
            "Plain ASCII with a hyphen-minus - and a --flag.",
            'let placeholder = "\\u{2014}"',
            "https://www.distronode.com/pricing and https://livekit-wss.distronode.com",
            "mode: .internal, KnowledgeMode" + internal + ", internalize, .localizedDescription",
            "https://stt.example.com and ada@contract.test and https://api.example.org",
            "the origin of the request, origins.example.com, originate.distronode.com",
            "github.com/distronode-corporation/district-core-swift",
        ]
    )

    cases: list[tuple[str, str, str, set[str]]] = [
        ("clean sample", "Sources/x.swift", clean, set()),
        ("em dash", "Sources/x.swift", f"one{em}two", {"dash"}),
        ("en dash", "README.md", f"pages 1{en}2", {"dash"}),
        ("dash in a mirrored contract", "contracts/mobile/a.json", f"one{em}two", set()),
        ("host in a mirrored contract", "contracts/desktop/a.json", "https://db" + internal + "/x", {"host"}),
        ("an .internal host", "Tests/x.swift", "https://llm" + internal + "/v1", {"host"}),
        ("a cluster-local service", "x.yml", "redis.default.svc.cluster" + ".local:6379", {"host"}),
        ("a .local host", "x.md", "build-box" + ".local", {"host"}),
        ("an origin host", "x.md", "https://origin-us." + "distronode.com/api", {"host"}),
        ("a bare origin host", "x.md", "origin." + "distronode.ca", {"host"}),
        ("a GitLab URL", "x.md", f"https://{lab}.com/group/project", {"gitlab"}),
        ("a self-managed GitLab", "x.md", f"{lab}.example.org/a/b", {"gitlab"}),
        ("an identifier, not a host", "x.py", "GIT" + "LAB.finditer(line)", set()),
    ]

    failures = 0
    for name, path, text, expected in cases:
        got = {f.rule for f in scan_text(text, path)}
        ok = got == expected
        failures += not ok
        print(f"  {'pass' if ok else 'FAIL'}  {name}: expected {sorted(expected)}, got {sorted(got)}")

    # Which files the scan reads: tracked and untracked-but-not-ignored text files
    # are read; ignored files and binary files are not.
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp)
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        bad = f"a{em}b\n"
        (repo / ".gitignore").write_text("ignored.txt\n", encoding="utf-8")
        (repo / "tracked.txt").write_text(bad, encoding="utf-8")
        (repo / "untracked.txt").write_text(bad, encoding="utf-8")
        (repo / "ignored.txt").write_text(bad, encoding="utf-8")
        (repo / "binary.bin").write_bytes(b"\0" + bad.encode("utf-8"))
        subprocess.run(["git", "add", "tracked.txt"], cwd=repo, check=True)
        _, findings = scan_tree(repo)
        got = sorted({f.path for f in findings})
        expected = ["tracked.txt", "untracked.txt"]
        ok = got == expected
        failures += not ok
        print(f"  {'pass' if ok else 'FAIL'}  file selection: expected {expected}, got {got}")

    if failures:
        print(f"\nself-test FAILED: {failures} case(s) did not answer as expected", file=sys.stderr)
        return 1
    print(f"\nself-test passed: {len(cases) + 1} cases")
    return 0


def main(argv: list[str]) -> int:
    if argv[1:] == ["--self-test"]:
        return self_test()
    if len(argv) > 1:
        print(__doc__, file=sys.stderr)
        return 2

    scanned, findings = scan_tree(ROOT)
    for finding in findings:
        print(finding)
    if findings:
        print(f"\n{len(findings)} finding(s) in {scanned} files", file=sys.stderr)
        return 1
    print(f"{scanned} files scanned, no findings")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
