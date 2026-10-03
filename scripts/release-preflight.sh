#!/usr/bin/env bash
#
# Decide what a release run builds, and refuse a ref that must not be released.
#
#   RELEASE_REF_TYPE=tag RELEASE_REF_NAME=v1.0 scripts/release-preflight.sh
#
# Called by .github/workflows/release.yml (both lanes) and submit.yml before anything is
# built. The ref defaults to the run's own (GITHUB_REF_TYPE, GITHUB_REF_NAME); submit.yml
# passes the tag it was asked to submit instead. Copied from district-ios's script of the
# same name, with this app's build-number offset, the Sparkle key check and the train
# check added.
#
# Prints, and appends to $GITHUB_OUTPUT when it is set:
#   version=<MARKETING_VERSION from project.yml>
#   build=<BUILD_NUMBER_OFFSET (default 20000) + git rev-list --count HEAD>
#   kind=tag|main
#
# Refuses:
#   - a shallow clone. `git rev-list --count` on one answers the depth (1), not the
#     history, and the build number would collide with one App Store Connect has seen;
#   - a tag that is not v<MARKETING_VERSION>, because a build attaches only to the
#     App Store version record whose string equals its CFBundleShortVersionString;
#   - a tag whose commit is not on main;
#   - a branch other than main;
#   - a project.yml whose SUPublicEDKey is missing, duplicated, still the scaffold's
#     placeholder, or not a base64 Ed25519 public key: the Developer ID build would ship
#     with Sparkle unable to accept any update, and that copy could never be fixed by
#     an update;
#   - with RELEASE_CHECK_UPLOADED=1, a build number not above the highest App Store
#     Connect already has for this version (it refuses a number at or below that, so
#     a tag of a commit a main dispatch already uploaded would spend a whole archive to
#     be turned away), and a version whose train App Store Connect has closed (a
#     version at or below one already approved on the Mac, which it refuses at the
#     upload, after the whole archive). Needs ASC_KEY_ID, ASC_ISSUER_ID and
#     ASC_KEY_PATH. release.yml's App Store job runs the preflight a second time with
#     it, once the key is fetched; submit.yml never sets it, because the build it
#     submits is uploaded by design.
#
# ⛔ THE OFFSET IS 20000, NOT district-ios's 4101. The Mac app is the same App Store
# Connect record as the iPhone and iPad app (one universal purchase). App Store Connect
# keeps a pre-release train per platform, and on 2026-10-03 it held iOS builds 3107 to
# 4116 and no Mac build at all, but nothing Apple documents promises that the two
# platforms' numbers can never meet. 20000 plus this repository's commit count stays
# clear of the iOS numbers (4101 plus district-ios's count) for as long as either
# repository is likely to exist, so the question never has to be answered.
set -euo pipefail

die() {
  echo "FATAL - $*" >&2
  exit 1
}

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REF_TYPE="${RELEASE_REF_TYPE:-${GITHUB_REF_TYPE:-}}"
REF_NAME="${RELEASE_REF_NAME:-${GITHUB_REF_NAME:-}}"

[ "$(git rev-parse --is-shallow-repository)" = "false" ] ||
  die "this is a shallow clone, so the commit count and the build number would be wrong. Check out with fetch-depth: 0."

# Exactly one MARKETING_VERSION line, quoted, as project.yml writes it.
versions="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' project.yml)"
[ -n "$versions" ] || die "no MARKETING_VERSION in project.yml."
[ "$(printf '%s\n' "$versions" | wc -l | tr -d ' ')" = "1" ] ||
  die "more than one MARKETING_VERSION in project.yml; expected exactly one."
VERSION="$versions"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "MARKETING_VERSION '$VERSION' is not a version number."

COUNT="$(git rev-list --count HEAD)"
BUILD=$((${BUILD_NUMBER_OFFSET:-20000} + COUNT))

# Exactly one SUPublicEDKey line, a 32-byte key in base64, and not the placeholder the
# scaffold shipped with.
keys="$(sed -n 's/^[[:space:]]*SUPublicEDKey:[[:space:]]*\([^[:space:]#]*\)[[:space:]]*$/\1/p' project.yml)"
[ -n "$keys" ] || die "no SUPublicEDKey in project.yml; the Developer ID build cannot verify any update."
[ "$(printf '%s\n' "$keys" | wc -l | tr -d ' ')" = "1" ] ||
  die "more than one SUPublicEDKey in project.yml; expected exactly one."
case "$keys" in
  *REPLACE_WITH*) die "SUPublicEDKey in project.yml is still the placeholder '$keys'. Nothing was built." ;;
esac
[[ "$keys" =~ ^[A-Za-z0-9+/]{43}=$ ]] ||
  die "SUPublicEDKey '$keys' in project.yml is not a base64 Ed25519 public key. Nothing was built."

case "$REF_TYPE" in
  tag)
    [[ "$REF_NAME" =~ ^v[0-9]+(\.[0-9]+){1,2}$ ]] || die "tag '$REF_NAME' is not of the form v<version>."
    [ "${REF_NAME#v}" = "$VERSION" ] ||
      die "tag '$REF_NAME' does not match MARKETING_VERSION '$VERSION' in project.yml at that commit. Nothing was built."
    git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null ||
      die "origin/main is not in this clone, so the tag cannot be checked against it."
    git merge-base --is-ancestor HEAD refs/remotes/origin/main ||
      die "tag '$REF_NAME' points at a commit that is not on main. Nothing was built."
    KIND=tag
    ;;
  branch)
    [ "$REF_NAME" = "main" ] || die "branch '$REF_NAME' is not main. Releases run from main or a v* tag only."
    KIND=main
    ;;
  *)
    die "unknown ref type '$REF_TYPE' (expected tag or branch)."
    ;;
esac

if [ "${RELEASE_CHECK_UPLOADED:-}" = "1" ]; then
  highest="$(python3 scripts/asc_release.py highest-build --version "$VERSION")" ||
    die "could not read the builds App Store Connect has for $VERSION."
  [[ "$highest" =~ ^[0-9]+$ ]] || die "App Store Connect's highest build for $VERSION is '$highest', not a number."
  [ "$BUILD" -gt "$highest" ] ||
    die "build $BUILD of $VERSION is not above $highest, the highest App Store Connect already has, so the upload would be refused. Release a newer commit. Nothing was built."
  echo "highest uploaded build of $VERSION: $highest"
  python3 scripts/asc_release.py train-open --version "$VERSION" ||
    die "App Store Connect will not take a build of $VERSION. Nothing was built."
fi

out="version=$VERSION
build=$BUILD
kind=$KIND"
printf '%s\n' "$out"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf '%s\n' "$out" >>"$GITHUB_OUTPUT"
fi
