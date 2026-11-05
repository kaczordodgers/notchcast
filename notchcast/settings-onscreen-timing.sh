#!/bin/zsh
set -euo pipefail
(( $# >= 2 && $# <= 3 )) || { echo "usage: $0 <Debug.app> <empty out dir> [slugs]"; exit 2; }
here=${0:A:h}
bundle=${1:A}
out=${2:A}
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")
[[ $identifier == app.notchcast.dev ]] || { echo 'Debug app required'; exit 2; }
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")
mkdir -p "$out"
[[ -z $(ls -A "$out") ]] || { echo "Output must be empty: $out"; exit 2; }
scratch=$(mktemp -d "${TMPDIR:-/tmp}/nc-settings-onscreen.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/tmp"
export NOTCHCAST_GALLERY_SCRATCH=$scratch
export NOTCHCAST_GALLERY_BUNDLE_ID=$identifier
export NOTCHCAST_GALLERY=$out
export NOTCHCAST_GALLERY_SETTINGS=1
export NOTCHCAST_SETTINGS_ONSCREEN=1
export NOTCHCAST_SETTINGS_TABS=${3:-notchcast}
sysctl -n vm.loadavg > "$out/loadavg-before.txt"
status_code=0
python3 "$here/gallery/isolate.py" "$scratch" "$out" "$bundle" "$executable" || status_code=$?
sysctl -n vm.loadavg > "$out/loadavg-after.txt"
(( status_code == 0 )) || exit "$status_code"
[[ -s $out/timings.json ]] || { echo 'Missing timings.json'; exit 1; }
