#!/usr/bin/env bash
#
# Harness for release-publish.sh's `notes`, the GitHub Release body publish.yml writes
# (and keeps as the dry run's release-notes.md). Offline: `notes` reads only the tree.
#
#   bash scripts/release-publish.test.sh
#
# ⛔ THE BODY IS THE DIRECT DOWNLOAD'S NOTES, NEVER THE MAC APP STORE'S. Until this test,
# `notes` asked asc_release.py for English without --direct, so a version with
# release-notes/en-US/<version>-mas.txt published the store's text on GitHub: 3.0.2's
# Release began "District AI is now in Canadian French", which the direct download had
# shipped in 3.0.0. 3.0.2 is the fixture because its store and CHANGELOG notes differ.
#
# ⚠️ NO `set -e`: a case that fails must still report.
set -uo pipefail

for _leaked in $(env 2>/dev/null | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | grep -E '^(TAG$|SOURCE_REF$|GITHUB_)'); do
  unset "$_leaked"
done

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$HERE/release-publish.sh"
PASS=0
FAIL=0
fail() {
  FAIL=$((FAIL + 1))
  echo "  x $1"
}
ok() {
  PASS=$((PASS + 1))
  echo "  . $1"
}
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) fail "$3 - expected to find: $2" ;; esac }
assert_lacks() { case "$1" in *"$2"*) fail "$3 - found: $2" ;; *) ok "$3" ;; esac }

work="$(mktemp -d "${TMPDIR:-/tmp}/release-publish-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
: >"$work/DistrictAI-3.0.2-20100.dmg"

echo "notes (v3.0.2, which has Mac App Store notes of its own)"
out="$(TAG=v3.0.2 bash "$SCRIPT" notes "$work" 2>/dev/null)"
status=$?
[ "$status" = "0" ] && ok "exits 0" || fail "exits 0 - got $status"
first_store="$(head -n 1 "$ROOT/release-notes/en-US/3.0.2-mas.txt")"
first_changelog="$(sed -n '/^## \[3.0.2\]/,/^## \[/p' "$ROOT/CHANGELOG.md" | sed -n '3p' | sed 's/^- //')"
[ -n "$first_store" ] && [ -n "$first_changelog" ] || fail "fixture: the 3.0.2 notes are where this test expects them"
assert_contains "$out" "$first_changelog" "the body opens with the CHANGELOG section"
assert_lacks "$out" "$first_store" "the body carries none of the store's -mas notes"
assert_contains "$out" "DistrictAI-3.0.2-20100.dmg" "the download section names the .dmg"

echo "notes (a version with no CHANGELOG section)"
: >"$work/DistrictAI-9.9-20100.dmg"
rm -f "$work/DistrictAI-3.0.2-20100.dmg"
TAG=v9.9 bash "$SCRIPT" notes "$work" >/dev/null 2>&1
status=$?
[ "$status" != "0" ] && ok "refused" || fail "refused - exited 0"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
