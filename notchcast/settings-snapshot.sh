#!/bin/zsh
set -euo pipefail
(( $# >= 2 && $# <= 3 )) || { echo "usage: $0 <Debug.app> <out> [slugs]"; exit 2; }
here=${0:A:h}
bundle=${1:A}
out=${2:A}
mkdir -p "${NOTCHCAST_SCRATCH:=$HOME/Library/Caches/notchcast}"
scratch=$(mktemp -d "$NOTCHCAST_SCRATCH/settings-snap.XXXXXX")
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")
[[ $identifier == app.notchcast.dev ]] || { echo 'Debug app required'; exit 2; }
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")
mkdir -p "$out" "$scratch/tmp"
[[ -z $(ls -A "$out") ]] || { echo "Output must be empty: $out"; exit 2; }
export NOTCHCAST_GALLERY_SCRATCH=$scratch
export NOTCHCAST_GALLERY_BUNDLE_ID=$identifier
export NOTCHCAST_GALLERY=$out
export NOTCHCAST_GALLERY_SETTINGS=1
export NOTCHCAST_SETTINGS_TABS=${3:-notchcast}
"$here/gallery/offscreen-check.sh" -- python3 "$here/gallery/isolate.py" "$scratch" "$out" "$bundle" "$executable"
[[ -s $out/timings.json ]] || { echo 'Missing timings.json'; exit 1; }
swift "$here/gallery/check-pixels.swift" "$out"
