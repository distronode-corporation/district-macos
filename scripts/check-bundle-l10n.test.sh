#!/usr/bin/env bash
#
# Tests for scripts/check-bundle-l10n.sh, on fake app bundles. Linux or macOS.
#
#   bash scripts/check-bundle-l10n.test.sh
#
# Each case builds a bundle in a scratch directory and asserts the verdict: the exit
# status, and for a refusal the line that names the problem.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-bundle-l10n.sh"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

passed=0
failed=0

# A bundle with the given files under Contents/Resources (paths relative to it), in a
# directory of its own. ⚠️ `mktemp`, not a counter: this runs in a command substitution,
# so a counter would never move and every case would share one bundle.
bundle() {
  local app file
  app="$(mktemp -d "$SCRATCH/case.XXXXXX")/District AI.app"
  mkdir -p "$app/Contents/Resources"
  for file in "$@"; do
    mkdir -p "$(dirname "$app/Contents/Resources/$file")"
    echo '"k" = "v";' >"$app/Contents/Resources/$file"
  done
  echo "$app"
}

# expect <name> <0|1> <expected stderr substring or ""> <french value> <app>
expect() {
  local name="$1" want="$2" needle="$3" french="$4" app="$5" status=0 err
  err="$(DISTRICT_FRENCH="$french" bash "$CHECK" "$app" 2>&1 >/dev/null)" || status=$?
  if [ "$status" != "$want" ]; then
    echo "FAIL $name: exit $status, expected $want ($err)"
    failed=$((failed + 1))
  elif [ -n "$needle" ] && [[ "$err" != *"$needle"* ]]; then
    echo "FAIL $name: stderr did not say '$needle': $err"
    failed=$((failed + 1))
  else
    echo "ok   $name"
    passed=$((passed + 1))
  fi
}

EN=(en.lproj/Localizable.strings en.lproj/InfoPlist.strings)
FR=(fr-CA.lproj/Localizable.strings fr-CA.lproj/InfoPlist.strings)

expect "English only, French off" 0 "" "" "$(bundle "${EN[@]}")"
expect "English only, French off (NO)" 0 "" "NO" "$(bundle "${EN[@]}")"
expect "a root Localizable.strings shadows en.lproj" 1 "Localizable.strings at the root" "" \
  "$(bundle "${EN[@]}" Localizable.strings)"
expect "a root InfoPlist.strings shadows en.lproj" 1 "InfoPlist.strings at the root" "" \
  "$(bundle "${EN[@]}" InfoPlist.strings)"
expect "the push table only at the root" 1 "no en.lproj/Localizable.strings" "" \
  "$(bundle Localizable.strings en.lproj/InfoPlist.strings)"
expect "no InfoPlist table" 1 "no en.lproj/InfoPlist.strings" "" "$(bundle en.lproj/Localizable.strings)"
expect "fr-CA with French off" 1 "French is off" "" "$(bundle "${EN[@]}" "${FR[@]}")"
expect "fr-CA with French on" 0 "" "YES" "$(bundle "${EN[@]}" "${FR[@]}")"
expect "fr-CA with French on (1)" 0 "" "1" "$(bundle "${EN[@]}" "${FR[@]}")"
expect "French on with no fr-CA" 1 "no fr-CA.lproj/Localizable.strings" "YES" "$(bundle "${EN[@]}")"
expect "a plain fr.lproj, French on" 1 "fr.lproj, which is never shipped" "YES" \
  "$(bundle "${EN[@]}" "${FR[@]}" fr.lproj/Localizable.strings)"
expect "a plain fr.lproj, French off" 1 "fr.lproj, which is never shipped" "" \
  "$(bundle "${EN[@]}" fr.lproj/Localizable.strings)"

missing="$SCRATCH/missing.app"
expect "no Contents/Resources" 1 "no Contents/Resources" "" "$missing"

echo "$passed passed, $failed failed"
[ "$failed" = "0" ]
