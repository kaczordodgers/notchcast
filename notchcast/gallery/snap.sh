#!/bin/zsh
set -euo pipefail
here=${0:A:h}
root=${here:h:h}
out=
bundle=${NOTCHCAST_GALLERY_APP:-}
while (( $# )); do
  case $1 in
    --out) (( $# >= 2 )) || { echo 'snap: --out needs a directory'; exit 2; }; out=$2; shift 2 ;;
    --app) (( $# >= 2 )) || { echo 'snap: --app needs a Debug app'; exit 2; }; bundle=$2; shift 2 ;;
    *) echo "usage: $0 [--out <dir>] [--app <Debug.app>]"; exit 2 ;;
  esac
done
scratch=$(mktemp -d ~/agents/nc-design/gallery.XXXXXX)
out=${out:-$scratch/shots}
mkdir -p "$out"
out=${out:A}
[[ -z $(ls -A "$out") ]] || { echo "snap: output must be empty: $out"; exit 2; }
if [[ -z $bundle ]]; then
  cd "$root"
  xcodegen generate > "$scratch/generate.log" 2>&1
  derived=${NOTCHCAST_GALLERY_DERIVED_DATA:-$scratch/DerivedData}
  build=(xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO build)
  queue=$HOME/chad/bin/build-queue.py
  if [[ -f $queue ]]; then
    python3 "$queue" hold -- "${build[@]}" > "$scratch/build.log" 2>&1 || { tail -80 "$scratch/build.log"; exit 1; }
  else
    "${build[@]}" > "$scratch/build.log" 2>&1 || { tail -80 "$scratch/build.log"; exit 1; }
  fi
  bundle="$derived/Build/Products/Debug/Notchcast Dev.app"
fi
bundle=${bundle:A}
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")
[[ $identifier == app.notchcast.dev ]] || { echo 'snap: only a Debug gallery app is accepted'; exit 2; }
runhome=$scratch/home
mkdir -p "$runhome/Library/Preferences" "$scratch/tmp"
touch "$runhome/.notchcast-gallery-home"
export NOTCHCAST_GALLERY_SCRATCH=$scratch
export NOTCHCAST_GALLERY_BUNDLE_ID=$identifier
export NOTCHCAST_GALLERY=$out
"$here/offscreen-check.sh" -- python3 "$here/isolate.py" "$scratch" "$out" "$bundle" "$executable" > "$out/run.log" 2>&1 || { cat "$out/run.log"; exit 1; }
[[ -s $out/manifest.txt ]] || { echo 'snap: no manifest'; exit 1; }
count=0
while IFS= read -r page; do
  [[ $page != */* && $page == *.png ]] || { echo "snap: invalid page $page"; exit 1; }
  [[ -s $out/$page && -s $out/${page%.png}-layout.json ]] || { echo "snap: missing $page or layout"; exit 1; }
  (( count += 1 ))
done < "$out/manifest.txt"
python3 "$here/inventory.py" "$out"
python3 "$here/check-layout.py" "$out" > "$out/layout-check.log" || true
tail -1 "$out/layout-check.log"
tail -2 "$out/run.log"
echo "snap: PASS $count pages in $out"
echo "snap: layout findings in $out/layout-check.log"
