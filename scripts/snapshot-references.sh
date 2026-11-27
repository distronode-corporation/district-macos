#!/usr/bin/env bash
#
# Copy the screen snapshot images a CI run recorded into the reference folder, for review
# and commit.
#
#     scripts/snapshot-references.sh <run id>
#
# The `app` job uploads every image a snapshot test recorded (a screen with no reference yet)
# as the `snapshots` artifact, under `DistrictSnapshots/<suite>/`. This downloads it with
# `gh` and copies those images to `App/Tests/Snapshots/__Snapshots__/<suite>/`, replacing a
# file of the same name. Look at every image before committing it: a reference is what the
# test will hold the screen to.
#
# ⚠️ ONLY RECORDED IMAGES ARE COPIED. An image that FAILED a comparison sits in the artifact
# under the test file's name, not under `DistrictSnapshots`, and is left alone: replacing a
# reference because a screen changed is a decision, made by deleting the old reference and
# letting CI record the new one.
set -euo pipefail

run=${1:?usage: scripts/snapshot-references.sh <run id>}
repo=${GITHUB_REPOSITORY:-distronode-corporation/district-macos}
root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

gh run download "$run" -R "$repo" -n snapshots -D "$work"
if [ ! -d "$work/DistrictSnapshots" ]; then
  echo "run $run recorded no new snapshot images"
  exit 0
fi

copied=0
for dir in "$work"/DistrictSnapshots/*/; do
  suite=$(basename "$dir")
  target="$root/App/Tests/Snapshots/__Snapshots__/$suite"
  mkdir -p "$target"
  for image in "$dir"*.png; do
    [ -e "$image" ] || continue
    name=$(basename "$image")
    # A staged committed reference is in the same folder; copy only what is new or changed.
    if [ -e "$target/$name" ] && cmp -s "$image" "$target/$name"; then
      continue
    fi
    cp "$image" "$target/$name"
    echo "$suite/$name"
    copied=$((copied + 1))
  done
done
echo "$copied image(s) copied into App/Tests/Snapshots/__Snapshots__/"
