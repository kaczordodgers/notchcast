#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$HERE/update.sh" "$HERE/config.env" "$WORK/"
printf '#!/bin/bash\ntouch "$HOME/installed"\n' > "$WORK/install-app.sh"
chmod +x "$WORK/install-app.sh"
mkdir -p "$WORK/Fixture.app/Contents"
printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>app.notchcast</string><key>CFBundleShortVersionString</key><string>2.0.0</string></dict></plist>' > "$WORK/Fixture.app/Contents/Info.plist"
printf '#!/bin/bash\nvalue=$(head -1 "$HOME/idle")\nif [ "$(wc -l < "$HOME/idle")" -gt 1 ]; then sed 1d "$HOME/idle" > "$HOME/rest"; mv "$HOME/rest" "$HOME/idle"; fi\necho "$value"\ntouch "$HOME/checked"\n' > "$WORK/idle-command"
chmod +x "$WORK/idle-command"
export FIXTURE="$WORK/Fixture.app"
gh() {
    case "$1 $2" in
        'release list') echo v2.0.0 ;;
        'release download') touch "$HOME/downloaded" ;;
    esac
}
codesign() { return 0; }
shasum() { echo '95280FD4EC25303CCC1FE2AA2A5E8B0A1A757DCC certificate'; }
ditto() { cp -R "$FIXTURE" "$4/New.app"; }
xattr() { return 0; }
export -f gh codesign shasum ditto xattr
export NOTCHCAST_IDLE_COMMAND="$WORK/idle-command"
export NOTCHCAST_IDLE_POLL_SECONDS=0.01 NOTCHCAST_IDLE_POLL_LIMIT=2
run_case() {
    local name=$1 installed=$2 expected=$3 values=$4
    export HOME="$WORK/$name" NOTCHCAST_APP="$WORK/$name/App.app"
    mkdir -p "$HOME"
    printf '%b\n' "$values" > "$HOME/idle"
    if [ "$installed" = yes ]; then
        cp -R "$FIXTURE" "$NOTCHCAST_APP"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.0.0' "$NOTCHCAST_APP/Contents/Info.plist"
    fi
    bash "$WORK/update.sh" --install > "$HOME/log" 2>&1 || { cat "$HOME/log"; return 1; }
    if [ "$expected" = yes ]; then
        test -f "$HOME/installed"
        test -f "$HOME/downloaded"
    else
        test ! -f "$HOME/installed"
        if [ "$name" = becomes-busy ]; then
            test -f "$HOME/downloaded"
        else
            test ! -f "$HOME/downloaded"
        fi
    fi
    case "$name" in
        idle) grep -q 'idle 600 s' "$HOME/log" || { echo 'FAIL: missing idle gate on immediate install'; return 1; } ;;
        becomes-idle) grep -q 'waiting.*idle 10 s' "$HOME/log"; grep -q 'installing.*idle 400 s' "$HOME/log" ;;
        busy|becomes-busy) grep -q 'Mac in use; installing at the next run' "$HOME/log" ;;
        first) test ! -f "$HOME/checked" ;;
    esac
    echo "PASS: $name"
}
run_case idle yes yes 600
run_case becomes-idle yes yes '10\n400'
run_case busy yes no 10
run_case first no yes 10
run_case becomes-busy yes no '400\n10'
