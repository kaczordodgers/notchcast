#!/bin/zsh
# Frames of the island's motion on the comparison stage (GalleryStage), offscreen, from a Debug build.
# usage: stage.sh --out <dir> --launcher <launcher-root-dark.png> [--app <Debug.app>]
set -euo pipefail
here=${0:A:h}
root=${here:h:h}
out=
launcher=
bundle=${NOTCHCAST_GALLERY_APP:-}
while (( $# )); do
  case $1 in
    --out) out=$2; shift 2 ;;
    --launcher) launcher=$2; shift 2 ;;
    --app) bundle=$2; shift 2 ;;
    *) echo "usage: $0 --out <dir> --launcher <png> [--app <Debug.app>]"; exit 2 ;;
  esac
done
[[ -n $out && -f $launcher ]] || { echo 'stage: --out and an existing --launcher are required'; exit 2; }
scratch=$(mktemp -d "${NOTCHCAST_GALLERY_SCRATCH_ROOT:-${TMPDIR:-/tmp}}/notchcast-stage.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$out"
out=${out:A}
if [[ -z $bundle ]]; then
  cd "$root"
  xcodegen generate > "$scratch/generate.log" 2>&1
  derived=${NOTCHCAST_GALLERY_DERIVED_DATA:-$HOME/Library/Caches/NotchcastGallery/DerivedData}
  build=(xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO build)
  if [[ -n ${NOTCHCAST_BUILD_WRAPPER:-} ]]; then
    "$NOTCHCAST_BUILD_WRAPPER" "${build[@]}" > "$scratch/build.log" 2>&1 || { tail -80 "$scratch/build.log"; exit 1; }
  else
    "${build[@]}" > "$scratch/build.log" 2>&1 || { tail -80 "$scratch/build.log"; exit 1; }
  fi
  bundle="$derived/Build/Products/Debug/Notchcast Dev.app"
fi
bundle=${bundle:A}
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")
[[ $identifier == app.notchcast.dev ]] || { echo 'stage: only a Debug gallery app is accepted'; exit 2; }
cp "$launcher" "$scratch/launcher.png"
mkdir -p "$scratch/home/Library/Preferences" "$scratch/tmp"
touch "$scratch/home/.notchcast-gallery-home"
export NOTCHCAST_GALLERY_SCRATCH=$scratch
export NOTCHCAST_GALLERY_BUNDLE_ID=$identifier
export NOTCHCAST_GALLERY=$out
export NOTCHCAST_STAGE=$out
export NOTCHCAST_STAGE_LAUNCHER=$scratch/launcher.png
"$here/offscreen-check.sh" -- python3 "$here/isolate.py" "$scratch" "$out" "$bundle" "$executable" > "$out/run.log" 2>&1 || { cat "$out/run.log"; exit 1; }
grep '^stage: ' "$out/run.log"
