#!/usr/bin/env bash
#
# Notarise the exported Developer ID app, build and sign the .dmg, notarise that, and
# prove the result the way Gatekeeper will judge it.
#
#   VERSION=1.0 BUILD=20005 ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=... \
#     DIRECT_IDENTITY="Developer ID Application: ..." scripts/direct-package.sh
#
# Called by .github/workflows/release.yml's direct job after scripts/archive.sh exported
# DistrictMacDirect.app into $BUILD_DIR/export. Writes into $BUILD_DIR/out:
#   DistrictAI-<version>-<build>.dmg   signed, notarised and stapled
# scripts/sparkle-sign.sh then adds the update signature and the checksums.
#
# ⛔ EVERY CHECK BELOW CAN FAIL, AND EACH FAILURE STOPS THE RUN. The app is checked
# before notarisation (so Apple is not asked to judge a bundle that is already wrong) and
# again, with the .dmg, after stapling, from a read-only mount of the .dmg itself: that is
# the copy a user installs.
#
# Notarisation uses the App Store Connect key (`notarytool --key`), the same .p8 the
# export used; the path reaches argv, never the key.
set -euo pipefail

TEAM_ID="R935BA6767"
APP_NAME="DistrictMacDirect"
# ⚠️ THE NAME A USER SEES IN /Applications. The bundle is named after its target; the
# .dmg carries it under the app's display name. A bundle's directory name is not covered
# by its signature or by the notarisation ticket, so the rename changes neither.
DMG_APP_NAME="District AI"

die() {
  echo "FATAL - $*" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "${VERSION:-}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "VERSION '${VERSION:-}' is not a version number."
[[ "${BUILD:-}" =~ ^[0-9]+$ ]] || die "BUILD '${BUILD:-}' is not a build number."
[ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -f "${ASC_KEY_PATH:-}" ] ||
  die "ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (an existing .p8) are all required, for notarytool."
[ -n "${DIRECT_IDENTITY:-}" ] || die "DIRECT_IDENTITY is unset; the .dmg is signed with it."

BUILD_DIR="${BUILD_DIR:-$ROOT/DerivedData/release}"
APP="$BUILD_DIR/export/$APP_NAME.app"
OUT="$BUILD_DIR/out"
WORK="$BUILD_DIR/package"
DMG="$OUT/DistrictAI-$VERSION-$BUILD.dmg"
[ -d "$APP" ] || die "no exported app at $APP; run scripts/archive.sh with LANE=direct first."
rm -rf "$OUT" "$WORK"
mkdir -p "$OUT" "$WORK"

# ── Checks on a bundle, run before notarisation and again on the mounted .dmg ──
# Each nested Sparkle component is named, because `--deep` verification passes a bundle
# whose helpers are validly signed by the wrong team or without the hardened runtime,
# which notarisation then refuses (or, for an updater, which fails on a user's Mac).
check_app() {
  local app="$1" what="$2" info archs version component
  codesign --verify --deep --strict --verbose=2 "$app"
  info="$(codesign -dvv "$app" 2>&1)"
  case "$info" in *"Authority=Developer ID Application: "*"($TEAM_ID)"*) ;; *) die "$what is not signed with this team's Developer ID Application certificate." ;; esac
  case "$info" in *"flags="*"runtime"*) ;; *) die "$what is not signed with the hardened runtime." ;; esac
  for component in \
    "Contents/Frameworks/Sparkle.framework" \
    "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
    "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
    "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" \
    "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"; do
    [ -e "$app/$component" ] || die "$what has no $component."
    info="$(codesign -dvv "$app/$component" 2>&1)"
    case "$info" in *"TeamIdentifier=$TEAM_ID"*) ;; *) die "$what: $component is not signed by team $TEAM_ID." ;; esac
    case "$info" in *"flags="*"runtime"*) ;; *) die "$what: $component is not signed with the hardened runtime." ;; esac
    echo "  signed, team $TEAM_ID, hardened runtime: $component"
  done
  # ⛔ A Developer ID build must not carry get-task-allow (a debuggable build, which
  # notarisation refuses) and must carry the sandbox (the same rules as the store build).
  codesign -d --entitlements - --xml "$app" 2>/dev/null >"$WORK/entitlements.plist"
  if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$WORK/entitlements.plist" >/dev/null 2>&1; then
    die "$what is signed with get-task-allow."
  fi
  [ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$WORK/entitlements.plist")" = "true" ] ||
    die "$what is not sandboxed."
  [ -f "$app/Contents/embedded.provisionprofile" ] || die "$what has no embedded provisioning profile."
  archs="$(lipo -archs "$app/Contents/MacOS/$APP_NAME")"
  case " $archs " in *" x86_64 "*) ;; *) die "$what is '$archs', with no x86_64 slice." ;; esac
  case " $archs " in *" arm64 "*) ;; *) die "$what is '$archs', with no arm64 slice." ;; esac
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
  [ "$version" = "$BUILD" ] || die "$what's CFBundleVersion is '$version', not $BUILD."
  echo "$what: signed for team $TEAM_ID, hardened runtime, sandboxed, $archs, build $version"
}

# ⛔ `--wait` ALONE IS NOT A VERDICT: notarytool exits 0 for a submission Apple marked
# Invalid. The status is read from the JSON, and Apple's log is printed when it is not
# Accepted, because that log is the only place the reason is written.
notarize() {
  local file="$1" result status id
  result="$(xcrun notarytool submit "$file" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
    --wait --timeout 45m --output-format json)" || {
    echo "$result"
    die "notarytool could not submit $(basename "$file")."
  }
  status="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
  id="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
  echo "notarisation of $(basename "$file"): $status (submission $id)"
  if [ "$status" != "Accepted" ]; then
    [ -n "$id" ] && xcrun notarytool log "$id" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" || true
    die "Apple did not accept $(basename "$file") for notarisation (status '$status')."
  fi
}

echo "== the exported app"
check_app "$APP" "the exported app"

echo "== notarise and staple the app"
ditto -c -k --keepParent "$APP" "$WORK/$APP_NAME.zip"
notarize "$WORK/$APP_NAME.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "== build, sign, notarise and staple the .dmg"
# ⚠️ HFS+, NOT APFS: an APFS disk image does not mount on every macOS this app supports
# the way HFS+ does, and nothing here needs APFS. UDZO is the compressed read-only format.
stage="$WORK/stage"
mkdir -p "$stage"
ditto "$APP" "$stage/$DMG_APP_NAME.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "District AI" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$DMG"
codesign --sign "$DIRECT_IDENTITY" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

echo "== verify the .dmg and the app inside it"
codesign --verify --strict --verbose=2 "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"
mnt="$WORK/mnt"
mkdir -p "$mnt"
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$DMG" >/dev/null
trap 'hdiutil detach "$mnt" -quiet >/dev/null 2>&1 || true' EXIT
check_app "$mnt/$DMG_APP_NAME.app" "the app in the .dmg"
xcrun stapler validate "$mnt/$DMG_APP_NAME.app"
spctl -a -t exec -vv "$mnt/$DMG_APP_NAME.app"
hdiutil detach "$mnt" -quiet
trap - EXIT

echo "dmg: $DMG"
