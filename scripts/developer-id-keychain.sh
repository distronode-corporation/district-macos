#!/usr/bin/env bash
#
# Put the Developer ID Application certificate and the Developer ID provisioning profile
# on this Mac for one release run, and take them away again.
#
#   GSM_ACCESS_TOKEN=<token> ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=... \
#     scripts/developer-id-keychain.sh setup <directory>
#   scripts/developer-id-keychain.sh teardown <directory>
#
# Called by .github/workflows/release.yml's direct job. The certificate signs what cloud
# signing cannot reach (the .dmg, which codesign signs with a private key on this
# machine) and, when the cloud export fails, the export itself, with the profile.
#
# setup writes, under <directory> (mode 0700):
#   release.keychain-db   a new keychain holding only the certificate and its key,
#                         unlocked, first in the user's search list
#   keychains.orig        the search list before, for teardown
#   devid.env             DIRECT_PROFILE_NAME=..., DIRECT_IDENTITY=... for $GITHUB_ENV
# and installs the profile where Xcode looks for one.
#
# teardown restores the search list, deletes the keychain and the installed profile and
# removes <directory>. It never fails the job: it runs in an `if: always()` step and
# reports what it could not undo.
#
# ⛔ The .p12 and its password come from Secret Manager (BRIDGEWATCH_APPLE_DEVELOPER_ID_P12_B64
# and BRIDGEWATCH_APPLE_DEVELOPER_ID_P12_PASSWORD: the team's one Developer ID Application
# certificate, JMMST2L825, shared with bridgewatch), are masked on GitHub Actions before
# anything can print them, and the .p12 is deleted as soon as it is imported.
# ⚠️ THE TWO PASSWORDS DO REACH argv: `security` takes the keychain password and the .p12
# password only as arguments (or from a prompt, which a runner cannot answer). That is
# bounded on purpose: the runner is a single-use VM, the keychain password is random for
# this run, and the .p12 file the password opens is deleted before anything else runs.
set -euo pipefail

# ⛔ THE PROFILE IS PINNED BY ID: "District macOS Developer ID", MAC_APP_DIRECT, for
# com.distronode.district with certificate JMMST2L825. It grants push, associated domains
# and the keychain group; Sign in with Apple is not in it (see project.yml).
PROFILE_ID="4F2465QW2Z"
IDENTITY="Developer ID Application: Distronode Corporation (R935BA6767)"

die() {
  echo "FATAL - $*" >&2
  exit 1
}

mask() {
  if [ -n "${GITHUB_ACTIONS:-}" ] && [ -n "$1" ]; then echo "::add-mask::$1"; fi
}

cmd="${1:-}"
dir="${2:-}"
[ -n "$dir" ] || die "usage: developer-id-keychain.sh setup|teardown <directory>"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_DIRS=("$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles")

case "$cmd" in
  setup)
    [ -n "${GSM_ACCESS_TOKEN:-}" ] || die "GSM_ACCESS_TOKEN is unset."
    umask 077
    mkdir -p "$dir"
    dir="$(cd "$dir" && pwd)"
    kc="$dir/release.keychain-db"
    p12="$dir/devid.p12"

    password="$("$ROOT/scripts/gsm-secret.sh" BRIDGEWATCH_APPLE_DEVELOPER_ID_P12_PASSWORD)"
    mask "$password"
    "$ROOT/scripts/gsm-secret.sh" BRIDGEWATCH_APPLE_DEVELOPER_ID_P12_B64 | base64 -D >"$p12"
    [ -s "$p12" ] || die "the Developer ID .p12 decoded to nothing."
    echo "Developer ID .p12: $(wc -c <"$p12" | tr -d ' ') bytes, password: ${#password} characters. Neither is printed."

    kc_password="$(openssl rand -hex 24)"
    mask "$kc_password"
    security list-keychains -d user | sed 's/^[[:space:]]*"\(.*\)"$/\1/' >"$dir/keychains.orig"
    security create-keychain -p "$kc_password" "$kc"
    # Locks after six hours idle and never on sleep: longer than any run.
    security set-keychain-settings -lut 21600 "$kc"
    security unlock-keychain -p "$kc_password" "$kc"
    security import "$p12" -k "$kc" -f pkcs12 -P "$password" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
    rm -f "$p12"
    unset password
    # ⛔ WITHOUT THE PARTITION LIST codesign waits for a keychain dialog nobody can click,
    # and the step hangs until its timeout.
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$kc_password" "$kc" >/dev/null
    unset kc_password
    # First in the search list, ahead of the login keychain, without dropping the others.
    orig=()
    while IFS= read -r line; do [ -n "$line" ] && orig+=("$line"); done <"$dir/keychains.orig"
    security list-keychains -d user -s "$kc" "${orig[@]}"

    identities="$(security find-identity -v -p codesigning "$kc")"
    case "$identities" in
      *"\"$IDENTITY\""*) echo "identity: $IDENTITY" ;;
      *) die "the keychain holds no valid '$IDENTITY'." ;;
    esac

    profile="$dir/devid.provisionprofile"
    meta="$(python3 "$ROOT/scripts/asc_release.py" profile --id "$PROFILE_ID" --out "$profile")"
    uuid="$(printf '%s\n' "$meta" | sed -n 's/^uuid=//p')"
    name="$(printf '%s\n' "$meta" | sed -n 's/^name=//p')"
    [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || die "profile $PROFILE_ID has no usable UUID."
    [[ "$name" =~ ^[A-Za-z0-9\ ._-]+$ ]] || die "profile $PROFILE_ID's name has characters this lane does not expect."
    : >"$dir/profiles.installed"
    for d in "${PROFILE_DIRS[@]}"; do
      mkdir -p "$d"
      cp "$profile" "$d/$uuid.provisionprofile"
      echo "$d/$uuid.provisionprofile" >>"$dir/profiles.installed"
    done
    echo "profile: $name ($uuid)"
    {
      echo "DIRECT_PROFILE_NAME=$name"
      echo "DIRECT_IDENTITY=$IDENTITY"
    } >"$dir/devid.env"
    ;;

  teardown)
    status=0
    if [ -f "$dir/keychains.orig" ]; then
      orig=()
      while IFS= read -r line; do [ -n "$line" ] && orig+=("$line"); done <"$dir/keychains.orig"
      if [ "${#orig[@]}" -gt 0 ]; then
        security list-keychains -d user -s "${orig[@]}" || status=1
      fi
    fi
    if [ -f "$dir/release.keychain-db" ]; then
      security delete-keychain "$dir/release.keychain-db" || status=1
    fi
    if [ -f "$dir/profiles.installed" ]; then
      while IFS= read -r installed; do rm -f "$installed" || status=1; done <"$dir/profiles.installed"
    fi
    rm -rf "$dir" || status=1
    if [ "$status" = "0" ]; then
      echo "the release keychain and profile are gone"
    else
      echo "::warning::could not undo every part of the release keychain setup; the runner is discarded with the job"
    fi
    ;;

  *) die "usage: developer-id-keychain.sh setup|teardown <directory>" ;;
esac
