#!/usr/bin/env bash
#
# Publish a Developer ID build that release.yml's `direct` job has already built:
# check it, make it an immutable GitHub Release, and write its appcast item.
#
#   TAG=v1.0 SOURCE_REF=refs/tags/v1.0 scripts/release-publish.sh verify  <dir>
#   TAG=v1.0 scripts/release-publish.sh appcast <dir> <appcast.xml>
#   TAG=v1.0 scripts/release-publish.sh notes   <dir>
#   TAG=v1.0 scripts/release-publish.sh release <dir>
#
# Called by .github/workflows/publish.yml, in that order. <dir> holds the direct job's
# artifact: DistrictAI-<version>-<build>.dmg, its .sig and SHA256SUMS. GH_TOKEN and
# GITHUB_REPOSITORY are read by `gh`; SOURCE_REF is the ref the build must have been
# made from (the tag for a release, refs/heads/main for a dry run of a main build).
#
#   verify   Refuses a set of files that is not exactly those three, a .dmg whose
#            version is not the tag's, a checksum that does not match, an EdDSA
#            signature that does not verify against the SUPublicEDKey in project.yml
#            (the key every installed copy trusts), and a .dmg without a build
#            provenance attestation from release.yml at SOURCE_REF. Writes the
#            attestation bundle beside the .dmg as <dmg>.intoto.jsonl and prints
#            version=, build=, dmg= and length= (also to $GITHUB_OUTPUT).
#   appcast  Adds the release to <appcast.xml> with scripts/appcast.py, pointing at
#            the asset URL the release will have. Nothing is published.
#   notes    Prints the release notes: the version's CHANGELOG section, then how to
#            check the download.
#   release  Creates the GitHub Release on the tag as a DRAFT with the four assets,
#            checks what GitHub stored, downloads the .dmg back and verifies its
#            checksum and attestation, and only then publishes it (the repository has
#            immutable releases on, so publishing is final). A release that is already
#            public is accepted only if it holds exactly these four files, byte for
#            byte (a re-run after a later step failed); anything else is refused.
#
# ⛔ `verify` RUNS FIRST AND `release` LAST. A dry run stops before `release`.
set -euo pipefail

die() {
  echo "FATAL - $*" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${GITHUB_REPOSITORY:-distronode-corporation/district-macos}"
SIGNER_WORKFLOW="$REPO/.github/workflows/release.yml"

command="${1:-}"
dir="${2:-}"
[ -n "$command" ] && [ -d "$dir" ] || die "usage: release-publish.sh verify|appcast|notes|release <dir> [appcast.xml]"
dir="$(cd "$dir" && pwd)"
[[ "${TAG:-}" =~ ^v[0-9]+(\.[0-9]+){1,2}$ ]] || die "TAG '${TAG:-}' is not of the form v<version>."
VERSION="${TAG#v}"

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
size() { wc -c <"$1" | tr -d ' '; }

# The .dmg in <dir>, by the name direct-package.sh gives it, with this tag's version.
find_dmg() {
  local dmgs
  dmgs=("$dir"/DistrictAI-*.dmg)
  [ "${#dmgs[@]}" = "1" ] && [ -f "${dmgs[0]}" ] || die "expected exactly one DistrictAI-*.dmg in $dir."
  DMG="$(basename "${dmgs[0]}")"
  [[ "$DMG" =~ ^DistrictAI-([0-9]+(\.[0-9]+){1,2})-([0-9]+)\.dmg$ ]] || die "'$DMG' is not DistrictAI-<version>-<build>.dmg."
  [ "${BASH_REMATCH[1]}" = "$VERSION" ] || die "'$DMG' is version ${BASH_REMATCH[1]}, not $VERSION from $TAG."
  BUILD="${BASH_REMATCH[3]}"
  SIG="$DMG.sig"
  BUNDLE="$DMG.intoto.jsonl"
}

verify() {
  [[ "${SOURCE_REF:-}" =~ ^refs/(tags/v[0-9.]+|heads/main)$ ]] || die "SOURCE_REF '${SOURCE_REF:-}' is not a v* tag or main."
  find_dmg

  # Exactly the three files the direct job writes, and nothing else, so a stray file
  # can never end up attached to the release.
  local expected actual
  expected="$(printf '%s\n' "$DMG" "$SIG" SHA256SUMS | sort)"
  actual="$(cd "$dir" && find . -maxdepth 1 -type f ! -name "$BUNDLE" | sed 's|^\./||' | sort)"
  [ "$expected" = "$actual" ] || die "$dir holds $(printf '%s' "$actual" | tr '\n' ' '), not exactly $DMG, $SIG and SHA256SUMS."

  # SHA256SUMS names exactly the .dmg and the .sig, and both match.
  [ "$(cut -d' ' -f3- "$dir/SHA256SUMS" | sort)" = "$(printf '%s\n' "$DMG" "$SIG" | sort)" ] ||
    die "SHA256SUMS does not list exactly $DMG and $SIG."
  (cd "$dir" && shasum -a 256 -c SHA256SUMS) || die "a checksum in SHA256SUMS does not match."

  # The update signature, against the key installed copies trust. sparkle-sign.sh did
  # this against the app inside the .dmg; this repeats it against project.yml at the
  # commit publishing it, so the item written below verifies in every installed copy.
  local signature public_key work openssl=""
  signature="$(cat "$dir/$SIG")"
  [[ "$signature" =~ ^[A-Za-z0-9+/]{86}==$ ]] || die "$SIG is not one base64 Ed25519 signature."
  public_key="$(sed -n 's/^[[:space:]]*SUPublicEDKey:[[:space:]]*\([A-Za-z0-9+/=]*\)[[:space:]]*$/\1/p' "$ROOT/project.yml")"
  [[ "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "no single SUPublicEDKey in project.yml."
  for candidate in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl "$(command -v openssl || true)"; do
    if [ -x "$candidate" ] && "$candidate" version 2>/dev/null | grep -q '^OpenSSL 3'; then
      openssl="$candidate"
      break
    fi
  done
  [ -n "$openssl" ] || die "no OpenSSL 3 found, which the Ed25519 verification needs."
  work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/publish.XXXXXX")"
  {
    # SubjectPublicKeyInfo for Ed25519: a fixed 12-byte prefix, then the 32-byte key.
    printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'
    printf '%s' "$public_key" | base64 --decode
  } >"$work/public.der"
  printf '%s' "$signature" | base64 --decode >"$work/signature.bin"
  if ! "$openssl" pkeyutl -verify -pubin -inkey "$work/public.der" -keyform DER -rawin \
    -in "$dir/$DMG" -sigfile "$work/signature.bin" >/dev/null; then
    rm -rf "$work"
    die "$SIG does not verify against project.yml's SUPublicEDKey; installed copies would refuse this update."
  fi
  rm -rf "$work"
  echo "EdDSA signature verified against project.yml's SUPublicEDKey"

  # The provenance attestation the direct job made, fetched from GitHub, kept as the
  # release's .intoto.jsonl (as bridgewatch attaches its own), and verified both
  # online and against that file: built by release.yml in this repository, from
  # SOURCE_REF, on a GitHub-hosted runner.
  local digest fetched
  digest="$(sha256 "$dir/$DMG")"
  work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/publish.XXXXXX")"
  (cd "$work" && gh attestation download "$dir/$DMG" --repo "$REPO" >/dev/null) ||
    die "no attestation for $DMG ($digest) in $REPO."
  fetched=("$work"/*.jsonl)
  [ "${#fetched[@]}" = "1" ] && [ -s "${fetched[0]}" ] || die "gh attestation download wrote no bundle for $DMG."
  mv "${fetched[0]}" "$dir/$BUNDLE"
  rm -rf "$work"
  local flags=(--repo "$REPO" --signer-workflow "$SIGNER_WORKFLOW" --source-ref "$SOURCE_REF" --deny-self-hosted-runners)
  gh attestation verify "$dir/$DMG" "${flags[@]}" >/dev/null || die "$DMG's attestation does not verify online."
  gh attestation verify "$dir/$DMG" "${flags[@]}" --bundle "$dir/$BUNDLE" >/dev/null ||
    die "$DMG does not verify against $BUNDLE."
  echo "attestation verified: $DMG, sha256:$digest, by $SIGNER_WORKFLOW at $SOURCE_REF"

  local out
  out="version=$VERSION
build=$BUILD
dmg=$DMG
length=$(size "$dir/$DMG")"
  printf '%s\n' "$out"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s\n' "$out" >>"$GITHUB_OUTPUT"
  fi
}

appcast() {
  local feed="${3:-}"
  [ -f "$feed" ] || die "no appcast at '$feed'."
  find_dmg
  local minimum
  # The deployment target, which is also LSMinimumSystemVersion in both builds.
  minimum="$(sed -n '/^[[:space:]]*deploymentTarget:/,/^[^[:space:]]/s/^[[:space:]]*macOS:[[:space:]]*"\([0-9.]*\)"[[:space:]]*$/\1/p' "$ROOT/project.yml")"
  [[ "$minimum" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "no single deploymentTarget macOS in project.yml."
  python3 "$ROOT/scripts/appcast.py" --feed "$feed" \
    --version "$VERSION" --build "$BUILD" \
    --url "https://github.com/$REPO/releases/download/$TAG/$DMG" \
    --length "$(size "$dir/$DMG")" \
    --signature "$(cat "$dir/$SIG")" \
    --minimum-system-version "$minimum" \
    --release-notes-url "https://github.com/$REPO/releases/tag/$TAG"
}

# The release notes: the version's CHANGELOG section (the App Store's notes, through the
# same reader, which refuses a missing or empty section), then how to check the download.
notes() {
  find_dmg
  python3 "$ROOT/scripts/asc_release.py" whats-new --version "$VERSION"
  echo
  echo "## Download"
  echo
  echo "\`$DMG\` is the Developer ID build: signed, notarised and stapled. Once installed, it keeps itself up to date."
  echo
  echo "Check the download before you open it:"
  echo
  echo '```sh'
  echo "shasum -a 256 -c SHA256SUMS"
  echo "gh attestation verify $DMG --repo $REPO"
  echo '```'
}

# The asset names and sha256 digests a release must hold, sorted, one `name sha256:x` per line.
expected_assets() {
  local f
  for f in "$DMG" "$SIG" SHA256SUMS "$BUNDLE"; do
    [ -s "$dir/$f" ] || die "$dir/$f is missing; run verify first."
    printf '%s sha256:%s\n' "$f" "$(sha256 "$dir/$f")"
  done | sort
}

stored_assets() {
  gh api "repos/$REPO/releases/$1" --jq '.assets[] | "\(.name) \(.digest)"' | sort
}

release() {
  find_dmg
  local expected id notes back
  expected="$(expected_assets)"

  # ⚠️ THE LIST, NOT releases/tags/<tag>: that endpoint never returns a draft.
  id="$(gh api "repos/$REPO/releases?per_page=100" --jq "[.[] | select(.tag_name == \"$TAG\" and (.draft | not))][0].id // empty")"
  if [ -n "$id" ]; then
    [ "$(stored_assets "$id")" = "$expected" ] ||
      die "$TAG is already published with different assets. A public release is never modified."
    echo "$TAG is already published with exactly these assets; nothing to do."
    return 0
  fi
  # A draft is invisible to users; one left by a failed run is deleted and rebuilt.
  for id in $(gh api "repos/$REPO/releases?per_page=100" --jq ".[] | select(.tag_name == \"$TAG\" and .draft) | .id"); do
    echo "deleting leftover draft $id of $TAG"
    gh api -X DELETE "repos/$REPO/releases/$id"
  done

  notes="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/notes.XXXXXX")"
  notes >"$notes"

  # --verify-tag: the tag must already exist; this never creates one.
  gh release create "$TAG" --repo "$REPO" --draft --verify-tag \
    --title "District AI for macOS $VERSION" --notes-file "$notes" \
    "$dir/$DMG" "$dir/$SIG" "$dir/SHA256SUMS" "$dir/$BUNDLE"
  rm -f "$notes"
  id="$(gh api "repos/$REPO/releases?per_page=100" --jq "[.[] | select(.draft and .tag_name == \"$TAG\")][0].id // empty")"
  [[ "$id" =~ ^[0-9]+$ ]] || die "the draft of $TAG was not found after it was created."

  # What GitHub stored, by name and digest, before anything is public.
  if [ "$(stored_assets "$id")" != "$expected" ]; then
    diff <(printf '%s\n' "$expected") <(stored_assets "$id") || true
    die "the draft of $TAG does not hold exactly the four files; it is left as a draft."
  fi

  # The .dmg as a user will download it, verified the way README tells them to.
  back="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/back.XXXXXX")"
  gh release download "$TAG" --repo "$REPO" --pattern "$DMG" --pattern SHA256SUMS --pattern "$SIG" --dir "$back"
  (cd "$back" && shasum -a 256 -c SHA256SUMS) || die "the draft's $DMG does not match its SHA256SUMS."
  gh attestation verify "$back/$DMG" --repo "$REPO" --signer-workflow "$SIGNER_WORKFLOW" --source-ref "refs/tags/$TAG" >/dev/null ||
    die "the draft's $DMG does not verify."
  rm -rf "$back"
  echo "the draft's assets match and its .dmg verifies"

  gh api -X PATCH "repos/$REPO/releases/$id" -F draft=false -f make_latest=true --jq '"published \(.tag_name): \(.html_url), immutable \(.immutable)"'
}

case "$command" in
  verify) verify ;;
  appcast) appcast "$@" ;;
  notes) notes ;;
  release) release ;;
  *) die "unknown command '$command' (verify, appcast, notes or release)." ;;
esac
