#!/usr/bin/env bash
#
# Sign the .dmg for Sparkle, prove the signature against the public key the app ships
# with, and write the checksums.
#
#   GSM_ACCESS_TOKEN=<token> scripts/sparkle-sign.sh <dmg>
#
# Called by .github/workflows/release.yml's direct job after scripts/direct-package.sh.
# Writes beside the .dmg:
#   <dmg>.sig      the EdDSA signature (base64, one line): the `sparkle:edSignature` of
#                  the appcast entry; its `length` is the .dmg's size in bytes
#   SHA256SUMS     sha256 of the .dmg and the .sig, as `shasum -a 256 -c` reads them
#
# ⛔ THE PRIVATE KEY NEVER TOUCHES THE DISK OR argv. It goes from Secret Manager
# (MACOS_SPARKLE_ED25519_KEY) straight into sign_update's standard input
# (`--ed-key-file -`); nothing here stores, echoes or masks-then-prints it.
# ⛔ THE SIGNATURE IS VERIFIED AGAINST THE APP'S OWN SUPublicEDKey, read from the app
# inside the .dmg, not against the private key it was made with. A key in Secret Manager
# that does not match the one compiled into installed copies would sign every update and
# every installed copy would refuse them all; this is the check that catches it.
set -euo pipefail

die() {
  echo "FATAL - $*" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dmg="${1:-}"
[ -f "$dmg" ] || die "usage: sparkle-sign.sh <dmg> (no file at '$dmg')"
[ -n "${GSM_ACCESS_TOKEN:-}" ] || die "GSM_ACCESS_TOKEN is unset."
dmg="$(cd "$(dirname "$dmg")" && pwd)/$(basename "$dmg")"
out="$(dirname "$dmg")"

# ⛔ sign_update FROM THE RESOLVED PACKAGE: the Sparkle 2.10.0 binary artifact SwiftPM
# downloaded into SourcePackages/ for the archive (archive.sh passes
# -clonedSourcePackagesDirPath) and checked against the checksum in Sparkle's
# Package.swift. Never one found elsewhere on the machine, which could be any version.
SIGN_UPDATE="${SIGN_UPDATE:-$ROOT/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update}"
[ -x "$SIGN_UPDATE" ] || die "no sign_update at $SIGN_UPDATE; run scripts/archive.sh with LANE=direct first."
echo "sign_update: $SIGN_UPDATE"

# Ed25519 verification needs OpenSSL 3: macOS's /usr/bin/openssl is LibreSSL.
OPENSSL=""
for candidate in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl "$(command -v openssl || true)"; do
  if [ -x "$candidate" ] && "$candidate" version 2>/dev/null | grep -q '^OpenSSL 3'; then
    OPENSSL="$candidate"
    break
  fi
done
[ -n "$OPENSSL" ] || die "no OpenSSL 3 found, which the Ed25519 verification needs."

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/sparkle.XXXXXX")"
mnt="$work/mnt"
cleanup() {
  hdiutil detach "$mnt" -quiet >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

# The public key the app in the .dmg carries.
mkdir -p "$mnt"
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$dmg" >/dev/null
apps=("$mnt"/*.app)
[ "${#apps[@]}" = "1" ] && [ -d "${apps[0]}" ] || die "expected exactly one app in the .dmg."
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${apps[0]}/Contents/Info.plist")"
hdiutil detach "$mnt" -quiet
[[ "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "the app's SUPublicEDKey is not a base64 Ed25519 public key."

signature="$("$ROOT/scripts/gsm-secret.sh" MACOS_SPARKLE_ED25519_KEY | "$SIGN_UPDATE" --ed-key-file - -p "$dmg")"
[[ "$signature" =~ ^[A-Za-z0-9+/]{86}==$ ]] || die "sign_update did not print one base64 Ed25519 signature."

# SubjectPublicKeyInfo for Ed25519 is a fixed 12-byte prefix plus the 32-byte key.
{
  printf '302a300506032b6570032100' | xxd -r -p
  printf '%s' "$public_key" | base64 -D
} >"$work/public.der"
printf '%s' "$signature" | base64 -D >"$work/signature.bin"
"$OPENSSL" pkeyutl -verify -pubin -inkey "$work/public.der" -keyform DER -rawin \
  -in "$dmg" -sigfile "$work/signature.bin" >/dev/null ||
  die "the signature does not verify against the app's SUPublicEDKey: the key in Secret Manager is not the key installed copies trust."
echo "EdDSA signature verified against the app's SUPublicEDKey"

printf '%s\n' "$signature" >"$dmg.sig"
(cd "$out" && shasum -a 256 "$(basename "$dmg")" "$(basename "$dmg").sig" >SHA256SUMS)
echo "length: $(stat -f %z "$dmg")"
cat "$out/SHA256SUMS"
