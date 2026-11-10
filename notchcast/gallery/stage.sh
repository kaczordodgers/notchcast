#!/bin/zsh
# Renders the island's motion stage (IslandMotionStage) into PNG frames, offscreen, in the gallery's sandbox.
# usage: stage.sh <empty output dir> <launcher-root-dark.png>
set -euo pipefail
here=${0:A:h}
root=${here:h:h}
(( $# == 2 )) || { echo "usage: $0 <empty output dir> <launcher png>"; exit 2; }
out=$1
launcher=${2:A}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/notchcast-stage.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$out"
out=${out:A}
[[ -z $(ls -A "$out") ]] || { echo "stage: output must be empty: $out"; exit 2; }
cd "$root"
xcodegen generate > "$scratch/generate.log" 2>&1
derived=${NOTCHCAST_GALLERY_DERIVED_DATA:-$HOME/Library/Caches/NotchcastGallery/DerivedData}
build=(xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO build)
if [[ -n ${NOTCHCAST_BUILD_WRAPPER:-} ]]; then
  "$NOTCHCAST_BUILD_WRAPPER" "${build[@]}" > "$scratch/build.log" 2>&1 || { tail -80 "$scratch/build.log"; exit 1; }
else
  "${build[@]}" > "$scratch/build.log" 2>&1 || { tail -80 "$scratch/build.log"; exit 1; }
fi
bundle="$derived/Build/Products/Debug/Notchcast Dev.app"
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")
cp "$launcher" "$scratch/launcher.png"
mkdir -p "$scratch/tmp"
export NOTCHCAST_GALLERY_SCRATCH=$scratch
export NOTCHCAST_GALLERY_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")
export NOTCHCAST_GALLERY=$out
export NOTCHCAST_MOTION_STAGE=$out
export NOTCHCAST_MOTION_LAUNCHER=$scratch/launcher.png
"$here/offscreen-check.sh" -- python3 "$here/isolate.py" "$scratch" "$out" "$bundle" "$executable"
