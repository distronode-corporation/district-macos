#!/usr/bin/env bash
#
# Check where a built app's string tables landed, and that French is in it only when it
# was switched on.
#
#   scripts/check-bundle-l10n.sh "path/to/District AI.app"
#   DISTRICT_FRENCH=YES scripts/check-bundle-l10n.sh "path/to/District AI.app"
#
# Run on every app this repository builds: by ci.yml after each of the two targets, by
# scripts/archive.sh on the archived app of both lanes (Mac App Store and Developer ID),
# which deletes the archive when it fails, and by scripts/direct-package.sh on the
# exported Developer ID app before it is notarised. Tested on Linux by
# scripts/check-bundle-l10n.test.sh. Exits 1 with one line per problem.
#
# ⛔ en.lproj HOLDS BOTH TABLES AND THE BUNDLE ROOT HOLDS NEITHER. macOS reads the push
# titles (Localizable) and the permission prompts (InfoPlist) from the bundle's .lproj
# tables; a table at the root of Contents/Resources shadows every .lproj, so a French
# table would never be read.
#
# ⛔ NO fr-CA.lproj UNLESS DISTRICT_FRENCH IS A TRUE VALUE, BOTH ITS TABLES WHEN IT IS, AND
# NEVER ANY OTHER FRENCH .lproj (fr.lproj, fr_CA.lproj, fr-FR.lproj, any case).
# French enters the app only through project.fr.yml, which `xcodegen generate` includes
# when DISTRICT_FRENCH is set. A French table in an English release would turn the
# notifications and the permission prompts French for every French Mac, and AppL10n would
# then turn the whole app French (it answers French when the bundle ships French), with
# French that has not been reviewed. A plain fr.lproj beside fr-CA.lproj would take every
# fr-FR, fr-BE and fr-CH Mac, which must read the Canadian French.
set -euo pipefail

APP="${1:-}"
[ -n "$APP" ] || { echo "usage: scripts/check-bundle-l10n.sh <app bundle>" >&2; exit 2; }
RES="$APP/Contents/Resources"
[ -d "$RES" ] || { echo "FATAL - no Contents/Resources in $APP" >&2; exit 1; }

case "${DISTRICT_FRENCH:-}" in
  YES | yes | true | TRUE | 1) french_on=1 ;;
  *) french_on=0 ;;
esac

problems=0
problem() {
  echo "FATAL - $*" >&2
  problems=$((problems + 1))
}

for table in Localizable InfoPlist; do
  [ -f "$RES/en.lproj/$table.strings" ] || problem "no en.lproj/$table.strings in the app."
  [ ! -e "$RES/$table.strings" ] || problem "$table.strings at the root of Contents/Resources shadows every .lproj."
done
# Every French .lproj in Contents/Resources: fr-CA.lproj by its exact name, and any other
# whose name starts with "fr" in any case (fr.lproj, fr_CA.lproj, fr-FR.lproj, FR.lproj,
# fr-ca.lproj). AppL10n turns the app French for ANY bundle localization starting with
# "fr", so a French table under another name is French switched on all the same.
# ⚠️ Contents/Resources ONLY, never Contents/Frameworks: Sparkle.framework carries its own
# fr.lproj (its update dialog), which is not this app's French and is not what AppL10n
# reads, so a recursive search would fail every Developer ID build.
has_fr_ca=0
shopt -s nocasematch
for lproj in "$RES"/*.lproj; do
  [ -d "$lproj" ] || continue
  name="${lproj##*/}"
  if [ "$name" = "fr-CA.lproj" ]; then
    has_fr_ca=1
  elif [[ "$name" == fr* ]]; then
    problem "the app holds $name, which is never shipped (fr-CA.lproj is the only French)."
  fi
done
shopt -u nocasematch
if [ "$french_on" = "1" ]; then
  for table in Localizable InfoPlist; do
    [ -f "$RES/fr-CA.lproj/$table.strings" ] || problem "DISTRICT_FRENCH is on, but the app has no fr-CA.lproj/$table.strings."
  done
elif [ "$has_fr_ca" = "1" ]; then
  problem "the app holds fr-CA.lproj, but DISTRICT_FRENCH is not set, so French is off."
fi

[ "$problems" = "0" ] || exit 1
if [ "$french_on" = "1" ]; then
  echo "string tables ok - en.lproj and fr-CA.lproj, nothing at the root (DISTRICT_FRENCH is on)"
else
  echo "string tables ok - en.lproj holds both, nothing at the root, no French"
fi
