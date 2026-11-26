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
# Expected differences: none. Every file is compared; nothing is skipped.
#
# ⛔ SWIFT_DETERMINISTIC_HASHING=1 IS PART OF THE RECIPE. Parts of the Swift toolchain are
# written in Swift (the driver, the App Intents metadata extractor, optimizer passes),
# and a Swift Dictionary's iteration order follows a hash seed that is random per process
# unless this variable is set. district-ios's two clean builds differed in a version.json
# for that reason. The variable changes no source and no build setting; it only fixes the
# seed of the Swift tools the build runs.
#
# ⛔ SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO IS PART OF THE RECIPE. A Release build
# compiles each Swift module whole (WMO), and by default Xcode splits that compile across
# `-num-threads N` LLVM modules, N taken from the machine (3 on the GitHub runner). Which of
# the N object files a shared entity (a mangled-name reference, an Objective-C selector
# reference) lands in then varies, and the linker lays the binary out by object file: with it
# on, two clean builds of the same commit differed in the app binary's `__TEXT,__const` (x86_64
# slice, main run 45003646554) and in `__stubs` and `__objc_stubs` (arm64 slice, run
# 45785542723). It also ties the output to the builder's core count. Off, each module is one
# object file per architecture, whatever the machine. The setting changes the code generation's
# partitioning only, not the optimisation level.
#
# On a difference it prints each differing file and each differing intermediate object file,
# and keeps both products and those object files under $RUNNER_TEMP/repeatable (or
# /tmp/repeatable) for the job to upload.
set -euo pipefail

scheme=$1
destination=$2
product=$3
OUT=${RUNNER_TEMP:-/tmp}/repeatable
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
    CODE_SIGNING_ALLOWED=NO \
    SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO > "$OUT/build-$n.log" 2>&1 || {
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
  # Every intermediate object file too, for the diagnosis below: a product that differs
  # names the object files it was linked from that differ.
  (cd DerivedData/Build/Intermediates.noindex && find . -type f -name '*.o' -print0 | sort -z | xargs -0 shasum -a 256) \
    > "$OUT/$n.objects.sha256"
  mkdir -p "$OUT/$n.objects"
  (cd DerivedData/Build/Intermediates.noindex && find . -type f -name '*.o' -print0 | xargs -0 -I{} rsync -R "{}" "$OUT/$n.objects/")
done

if diff -u "$OUT/1.sha256" "$OUT/2.sha256" > "$OUT/sha256.diff"; then
  rm -rf "$OUT/1.objects" "$OUT/2.objects"
  echo "PASS: both unsigned builds of $(basename "$product") are byte for byte identical"
  exit 0
fi

echo "FAIL: the two builds differ in these files:"
grep -E '^[-+]([0-9a-f]{64}|link) ' "$OUT/sha256.diff" | sed -E 's/^[-+]([0-9a-f]{64}|link)  //; s/ -> .*$//' | sort -u | tee "$OUT/differing.txt"
# The object files that differ, kept from both builds for the artifact; the rest are dropped.
echo "Intermediate object files that differ:"
diff "$OUT/1.objects.sha256" "$OUT/2.objects.sha256" | grep -E '^[<>] ' | sed -E 's/^[<>] [0-9a-f]{64}  //' | sort -u \
  | tee "$OUT/differing-objects.txt"
for n in 1 2; do
  mkdir -p "$OUT/objects-$n"
  (cd "$OUT/$n.objects" && xargs -I{} rsync -R "{}" "$OUT/objects-$n/" < "$OUT/differing-objects.txt") || true
  rm -rf "$OUT/$n.objects"
done
exit 1
