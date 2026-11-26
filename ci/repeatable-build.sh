#!/usr/bin/env bash
#
# Build the app UNSIGNED, in Release, twice from clean, and fail unless every file in
# the two products is byte for byte the same.
#
#     ci/repeatable-build.sh <scheme> <destination> <product>
#     ci/repeatable-build.sh DistrictMac 'generic/platform=macOS' 'Release/District AI.app'
#
# Each build deletes DerivedData first, so the second cannot reuse the first one's
# outputs. Both use the same DerivedData path and the same resolved SourcePackages, so
# paths embedded in the binaries are the same too. CODE_SIGNING_ALLOWED=NO: no
# signature to strip before comparing (CI's other builds sign ad hoc; this one does not
# sign at all), and no Apple account needed.
#
# Expected differences: one file, compared apart below and never skipped unchecked:
#   District AI.app/Contents/Frameworks/Sentry.framework/Versions/A/Sentry
# The app links the STATIC `Sentry` product (kept on purpose: the dynamic one adds about 47 MB),
# so Sentry's code is inside the app binary, and Xcode embeds Sentry.framework only to carry its
# Info.plist and privacy manifest, "injecting a stub binary into codeless framework". That stub
# is linked in a fresh random `swbuild.tmp.*` directory, whose path becomes its LC_ID_DYLIB and
# feeds its LC_UUID and code signature, so it differs between any two builds and cannot be
# normalised after the fact (the UUID is a hash of the whole file). Instead, in each build the
# script proves the stub holds no code (an empty __TEXT,__text and no symbols, for each
# architecture), that its install name is the swbuild.tmp path and nothing else, and that the
# app binary does not load it; and it compares the two stubs' load commands with only the
# install name and the UUID taken out. Every other file is compared byte for byte.
#
# ⛔ SWIFT_DETERMINISTIC_HASHING=1 IS PART OF THE RECIPE. Parts of the Swift toolchain are
# written in Swift (the driver, the App Intents metadata extractor, optimizer passes),
# and a Swift Dictionary's iteration order follows a hash seed that is random per process
# unless this variable is set. district-ios's two clean builds differed in a version.json
# for that reason. The variable changes no source and no build setting; it only fixes the
# seed of the Swift tools the build runs.
#
# ⛔ Reproducible.xcconfig IS PART OF THE RECIPE, passed with -xcconfig, as the release archive
# (scripts/archive.sh) passes it: the one place the build settings for repeatability live (it
# says why there are no Objective-C selector stubs).
#
# On a difference it prints each differing file and each differing intermediate object file,
# and keeps both products and those object files under $RUNNER_TEMP/repeatable (or
# /tmp/repeatable) for the job to upload.
set -euo pipefail

scheme=$1
destination=$2
product=$3
OUT=${RUNNER_TEMP:-/tmp}/repeatable
STUB="$(basename "$product")/Contents/Frameworks/Sentry.framework/Versions/A/Sentry"
APP_BINARY="$(basename "$product")/Contents/MacOS/$(basename "$product" .app)"
export SWIFT_DETERMINISTIC_HASHING=1
rm -rf "$OUT"
mkdir -p "$OUT"

for n in 1 2; do
  echo "== build $n"
  rm -rf DerivedData
  xcodebuild build \
    -project DistrictMac.xcodeproj \
    -scheme "$scheme" \
    -configuration Release \
    -destination "$destination" \
    -derivedDataPath DerivedData \
    -clonedSourcePackagesDirPath SourcePackages \
    -xcconfig Reproducible.xcconfig \
    CODE_SIGNING_ALLOWED=NO > "$OUT/build-$n.log" 2>&1 || {
      tail -n 100 "$OUT/build-$n.log"
      exit 1
    }
  mkdir -p "$OUT/$n"
  # ditto keeps symlinks inside bundles as symlinks.
  ditto "DerivedData/Build/Products/$product" "$OUT/$n/$(basename "$product")"
  # Regular files by content, plus every symbolic link by its literal target (not
  # followed), so an added, removed or retargeted link (e.g. Versions/Current) differs too.
  (cd "$OUT/$n" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256) > "$OUT/$n.sha256"
  (cd "$OUT/$n" && find . -type l -print0 | sort -z | while IFS= read -r -d '' l; do
    printf 'link  %s -> %s\n' "$l" "$(readlink "$l")"
  done) >> "$OUT/$n.sha256"
  echo "$(wc -l < "$OUT/$n.sha256" | tr -d ' ') files in build $n"
  # The codeless Sentry stub, checked here and compared apart (see the top of this file).
  stub="$OUT/$n/$STUB"
  [ -f "$stub" ] || { echo "FAIL: no Sentry stub at $STUB in build $n"; exit 1; }
  for arch in $(lipo -archs "$stub"); do
    text=$(otool -arch "$arch" -l "$stub" | awk '/sectname __text/{t=1} t && /^ *size/{print $2; exit}')
    [ "$text" = 0x0000000000000000 ] || { echo "FAIL: the Sentry stub's $arch __text is $text, not empty"; exit 1; }
    nm -arch "$arch" "$stub" 2>&1 | grep -q 'no symbols' || { echo "FAIL: the Sentry stub's $arch slice has symbols"; exit 1; }
    otool -arch "$arch" -D "$stub" | tail -n +2 | grep -Eq '/swbuild\.tmp\.[^/]+/' \
      || { echo "FAIL: the Sentry stub's $arch install name is not the swbuild.tmp path"; exit 1; }
  done
  if otool -L "$OUT/$n/$APP_BINARY" | grep -q 'Sentry\.framework'; then
    echo "FAIL: the app binary loads Sentry.framework, so its stub is not codeless padding"
    exit 1
  fi
  # Each architecture's load commands, without the file-name headers otool prints.
  for arch in $(lipo -archs "$stub"); do
    echo "== $arch"
    otool -arch "$arch" -l "$stub" | tail -n +2 | grep -vE '^ +name .*/swbuild\.tmp\.|^ +uuid '
  done > "$OUT/$n.stub.txt"
  grep -vF "  ./$STUB" "$OUT/$n.sha256" > "$OUT/$n.sha256.tmp" && mv "$OUT/$n.sha256.tmp" "$OUT/$n.sha256"
  # Every intermediate object file too, for the diagnosis below: a product that differs
  # names the object files it was linked from that differ.
  (cd DerivedData/Build/Intermediates.noindex && find . -type f -name '*.o' -print0 | sort -z | xargs -0 shasum -a 256) \
    > "$OUT/$n.objects.sha256"
  mkdir -p "$OUT/$n.objects"
  (cd DerivedData/Build/Intermediates.noindex && find . -type f -name '*.o' -print0 | xargs -0 -I{} rsync -R "{}" "$OUT/$n.objects/")
done

if ! diff -u "$OUT/1.stub.txt" "$OUT/2.stub.txt"; then
  echo "FAIL: the two Sentry stubs differ in more than their install name and UUID"
  exit 1
fi
echo "Sentry stub: no code and no symbols in either build; identical but for the install name and UUID"

if diff -u "$OUT/1.sha256" "$OUT/2.sha256" > "$OUT/sha256.diff"; then
  rm -rf "$OUT/1.objects" "$OUT/2.objects"
  echo "PASS: both unsigned builds of $(basename "$product") are byte for byte identical"
  exit 0
fi

echo "FAIL: the two builds differ in these files:"
grep -E '^[-+]([0-9a-f]{64}|link) ' "$OUT/sha256.diff" | sed -E 's/^[-+]([0-9a-f]{64}|link)  //; s/ -> .*$//' | sort -u | tee "$OUT/differing.txt"
# The object files that differ, kept from both builds for the artifact; the rest are dropped.
echo "Intermediate object files that differ:"
# ⚠️ `|| true`: diff exits 1 on a difference and grep exits 1 on none, and either would end the
# script here under `set -euo pipefail` before the objects are kept.
{ diff "$OUT/1.objects.sha256" "$OUT/2.objects.sha256" || true; } | { grep -E '^[<>] ' || true; } \
  | sed -E 's/^[<>] [0-9a-f]{64}  //' | sort -u | tee "$OUT/differing-objects.txt"
for n in 1 2; do
  mkdir -p "$OUT/objects-$n"
  (cd "$OUT/$n.objects" && xargs -I{} rsync -R "{}" "$OUT/objects-$n/" < "$OUT/differing-objects.txt") || true
  rm -rf "$OUT/$n.objects"
done
exit 1
