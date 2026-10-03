#!/usr/bin/env bash
#
# Archive one of the app's two builds and export it. Runs on a Mac with Xcode.
#
#   LANE=appstore ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=... scripts/archive.sh
#   LANE=direct DIRECT_SIGNING=cloud ... scripts/archive.sh
#   LANE=direct DIRECT_SIGNING=manual DIRECT_PROFILE_NAME=... SKIP_ARCHIVE=1 scripts/archive.sh
#
# Called by .github/workflows/release.yml, one lane per job. Adapted from district-ios's
# scripts/archive-imac.sh; the differences are the two lanes and the ad hoc archive.
#
# ── The two lanes ────────────────────────────────────────────────────────────
#   appstore  `DistrictMac`, exported with ExportOptions-AppStore.plist, which UPLOADS
#             the signed package to App Store Connect (TestFlight receives it once
#             valid). Cloud signing: the App Store Connect key lets xcodebuild use
#             the team's cloud-managed distribution certificates and mint the profile.
#   direct    `DistrictMacDirect`, exported for Developer ID into $BUILD_DIR/export.
#             Nothing leaves the machine; scripts/direct-package.sh notarises it and
#             builds the .dmg. DIRECT_SIGNING picks how the export signs:
#               cloud   ExportOptions-DeveloperID.plist, automatic, with the key;
#               manual  the Developer ID certificate already in a keychain
#                       (scripts/developer-id-keychain.sh) and the provisioning profile
#                       named by DIRECT_PROFILE_NAME. SKIP_ARCHIVE=1 re-exports the
#                       archive a failed cloud export left behind.
#
# ── The archive is signed ad hoc, on purpose ─────────────────────────────────
# ⛔ `CODE_SIGN_IDENTITY=-` WITH THE TEAM SET. The export re-signs every binary in the
# bundle with the distribution identity, so the archive's own signature is thrown away;
# what the export keeps is the entitlements, and `$(AppIdentifierPrefix)` in the keychain
# group resolves only with DEVELOPMENT_TEAM set. Automatic signing at archive time would
# instead sign for development, which on macOS needs the build machine registered as a
# device: every fresh runner would add a Mac to the team's device list.
#
# ── Environment ──────────────────────────────────────────────────────────────
#   LANE            appstore | direct (required)
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH
#                   the App Store Connect key (required; the .p8 must exist; this script
#                   never reads, prints or copies it, it passes the PATH to xcodebuild)
#   DIRECT_SIGNING  cloud | manual (direct only; required there)
#   DIRECT_PROFILE_NAME  the Developer ID profile's name (manual only)
#   BUILD_DIR       archive and export output (default: DerivedData/release)
#   BUILD_NUMBER_OFFSET  added to the commit count (default: 20000; see release-preflight.sh)
#   SKIP_ARCHIVE=1  export the archive already in BUILD_DIR
#   ALLOW_DIRTY=1   proceed with a dirty working tree
#   ALLOW_BRANCH=1  proceed when HEAD is not on main (the workflow sets it for a tag,
#                   whose commit the preflight has already proved is on main)
#   SENTRY_DSN      the app's DSN (optional; blank DISABLES Sentry in the build: no SDK
#                   is started and nothing is reported)
#   SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT
#                   when the token is set, dSYMs are uploaded after the archive
set -euo pipefail

# ⚠️ Must equal <key>teamID</key> in both ExportOptions plists.
TEAM_ID="R935BA6767"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

die() {
  echo "FATAL - $*" >&2
  exit 1
}

HOST_OS="$(uname -s)"
[ "$HOST_OS" = "Darwin" ] || die "archive.sh runs on macOS only; uname -s reported '$HOST_OS'."

cd "$ROOT"

LANE="${LANE:-}"
case "$LANE" in
  appstore)
    SCHEME=DistrictMac
    ;;
  direct)
    SCHEME=DistrictMacDirect
    case "${DIRECT_SIGNING:-}" in
      cloud) ;;
      manual)
        [ -n "${DIRECT_PROFILE_NAME:-}" ] || die "DIRECT_SIGNING=manual needs DIRECT_PROFILE_NAME."
        ;;
      *) die "LANE=direct needs DIRECT_SIGNING=cloud or manual, not '${DIRECT_SIGNING:-}'." ;;
    esac
    ;;
  *) die "LANE must be appstore or direct, not '$LANE'." ;;
esac

# ⛔ THE BUILD NUMBER IS DERIVED FROM HEAD, so a dirty tree or a side branch would ship a
# number that maps to no commit anybody can check out.
if [ "${ALLOW_DIRTY:-0}" != "1" ]; then
  [ -z "$(git status --porcelain)" ] ||
    die "the working tree is dirty; commit or stash first, or set ALLOW_DIRTY=1 for a scratch build."
fi
if [ "${ALLOW_BRANCH:-0}" != "1" ]; then
  branch="$(git branch --show-current)"
  [ "$branch" = "main" ] ||
    die "HEAD is on '$branch' (empty means a detached HEAD), not main; set ALLOW_BRANCH=1 for a scratch build."
fi

ASC_KEY_ID="${ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
[ -n "$ASC_KEY_ID" ] || die "ASC_KEY_ID is unset. ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH are all required."
[ -n "$ASC_ISSUER_ID" ] || die "ASC_ISSUER_ID is unset. ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH are all required."
KEY_PATH="${ASC_KEY_PATH:-}"
[ -f "$KEY_PATH" ] || die "no App Store Connect key at '$KEY_PATH' (ASC_KEY_PATH). This script never writes or fetches it."
AUTH=(-allowProvisioningUpdates
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID")

# ⛔ NEVER ECHOED. A blank DSN switches Sentry off entirely, and the notice says so,
# because "no reports" and "unsymbolicated reports" look the same from outside.
SENTRY_DSN="${SENTRY_DSN:-}"
if [ -n "$SENTRY_DSN" ]; then
  echo "Using SENTRY_DSN from the environment. Its value is never printed."
else
  echo "SENTRY_DSN is unset - SENTRY IS DISABLED IN THIS BUILD: no SDK is started, so no crash or app hang is reported at all."
fi

BUILD_DIR="${BUILD_DIR:-$ROOT/DerivedData/release}"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
mkdir -p "$BUILD_DIR"

# ⛔ COMMIT COUNT PLUS AN OFFSET, the scheme release-preflight.sh documents; the two must
# agree, and the workflow checks the number this prints against the preflight's.
BUILD_NUMBER=$((${BUILD_NUMBER_OFFSET:-20000} + $(git rev-list --count HEAD)))

if [ "${SKIP_ARCHIVE:-0}" = "1" ]; then
  [ -d "$ARCHIVE_PATH" ] || die "SKIP_ARCHIVE=1 but there is no archive at $ARCHIVE_PATH."
  echo "SKIP_ARCHIVE=1 - exporting the archive already at $ARCHIVE_PATH."
else
  xcodegen generate --spec project.yml

  # ⛔ `generic/platform=macOS` builds every architecture in ARCHS (arm64 and x86_64 in
  # Release), not just the host's. Packages go to SourcePackages/ (gitignored), as in
  # ci.yml, which is where scripts/sparkle-sign.sh takes Sparkle's sign_update from.
  xcodebuild archive \
    -project DistrictMac.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    -clonedSourcePackagesDirPath SourcePackages \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    SENTRY_DSN="$SENTRY_DSN"

  # ⛔ THE BUNDLE IS CHECKED, NOT ASSUMED: a universal binary, the build number from
  # this commit, and (for the store) no Sparkle anywhere in it.
  APP="$ARCHIVE_PATH/Products/Applications/$SCHEME.app"
  [ -f "$APP/Contents/MacOS/$SCHEME" ] || die "no app binary at $APP/Contents/MacOS/$SCHEME. Nothing was exported."
  archs="$(lipo -archs "$APP/Contents/MacOS/$SCHEME")"
  case " $archs " in *" x86_64 "*) ;; *) die "the archived binary is '$archs', with no x86_64 slice." ;; esac
  case " $archs " in *" arm64 "*) ;; *) die "the archived binary is '$archs', with no arm64 slice." ;; esac
  echo "architectures: $archs"
  built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
  [ "$built" = "$BUILD_NUMBER" ] || die "the archived app's CFBundleVersion is '$built', not $BUILD_NUMBER."
  if [ "$LANE" = "appstore" ] && [ -e "$APP/Contents/Frameworks/Sparkle.framework" ]; then
    die "the App Store archive contains Sparkle.framework; App Review rejects it. Nothing was exported."
  fi

  # ⛔ THE INGEST HOST AND THE API HOST ARE DIFFERENT THINGS: sentry-cli does not read
  # the DSN and defaults to the US silo, where an EU org does not exist, and a
  # mis-pointed upload does nothing while the build stays green. The token reaches
  # sentry-cli through its environment, never argv.
  if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
    echo "SENTRY_AUTH_TOKEN is unset - skipped the dSYM upload; crashes from this build will not symbolicate."
  else
    [ -n "${SENTRY_ORG:-}" ] || die "SENTRY_AUTH_TOKEN is set but SENTRY_ORG is not; pass the EU org slug."
    [ -n "${SENTRY_PROJECT:-}" ] || die "SENTRY_AUTH_TOKEN is set but SENTRY_PROJECT is not."
    command -v sentry-cli >/dev/null 2>&1 || die "SENTRY_AUTH_TOKEN is set but sentry-cli is not on PATH."
    SENTRY_URL="https://de.sentry.io" sentry-cli debug-files upload \
      --org "$SENTRY_ORG" \
      --project "$SENTRY_PROJECT" \
      "$ARCHIVE_PATH/dSYMs"
  fi
fi

rm -rf "$EXPORT_PATH"
case "$LANE" in
  appstore)
    # ⚠️ The authentication flags again: the export is a separate invocation and
    # inherits nothing from the archive. `destination: upload` makes it the upload.
    xcodebuild -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportOptionsPlist ExportOptions-AppStore.plist \
      -exportPath "$EXPORT_PATH" \
      "${AUTH[@]}"
    ;;
  direct)
    if [ "$DIRECT_SIGNING" = "cloud" ]; then
      options="$ROOT/ExportOptions-DeveloperID.plist"
    else
      # The manual variant names the profile, which comes from the environment, so it is
      # written here rather than committed. PlistBuddy, not a heredoc, so a quote in the
      # name cannot break the XML.
      options="$BUILD_DIR/ExportOptions-DeveloperID-manual.plist"
      rm -f "$options"
      /usr/libexec/PlistBuddy \
        -c 'Add :method string developer-id' \
        -c 'Add :signingStyle string manual' \
        -c "Add :teamID string $TEAM_ID" \
        -c 'Add :signingCertificate string Developer ID Application' \
        -c 'Add :provisioningProfiles dict' \
        "$options" >/dev/null
      /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:com.distronode.district string $DIRECT_PROFILE_NAME" "$options" >/dev/null
    fi
    xcodebuild -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportOptionsPlist "$options" \
      -exportPath "$EXPORT_PATH" \
      "${AUTH[@]}"
    [ -d "$EXPORT_PATH/$SCHEME.app" ] || die "the export wrote no $SCHEME.app into $EXPORT_PATH."
    echo "exported: $EXPORT_PATH/$SCHEME.app ($DIRECT_SIGNING signing)"
    ;;
esac

echo "build number: $BUILD_NUMBER"
echo "archive: $ARCHIVE_PATH"
