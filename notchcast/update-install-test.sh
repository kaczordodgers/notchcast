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
ioreg() { touch "$HOME/idle-read"; echo '"HIDIdleTime" = 0'; }
sleep() { touch "$HOME/slept"; }
export -f gh codesign shasum ditto xattr ioreg sleep
run_case() {
    local name=$1 installed=$2
    shift 2
    export HOME="$WORK/$name" NOTCHCAST_APP="$WORK/$name/App.app"
    mkdir -p "$HOME"
    if [ "$installed" = yes ]; then
        cp -R "$FIXTURE" "$NOTCHCAST_APP"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.0.0' "$NOTCHCAST_APP/Contents/Info.plist"
    fi
    bash "$WORK/update.sh" "$@" > "$HOME/log" 2>&1 || { cat "$HOME/log"; return 1; }
    test -f "$HOME/downloaded" || { echo "FAIL: $name did not download"; return 1; }
    test -f "$HOME/installed" || { echo "FAIL: $name did not install"; cat "$HOME/log"; return 1; }
    test ! -f "$HOME/idle-read" || { echo "FAIL: $name read idle time"; return 1; }
    test ! -f "$HOME/slept" || { echo "FAIL: $name waited"; return 1; }
    ! grep -qiE 'idle|in use|next run' "$HOME/log" || { echo "FAIL: $name deferred"; cat "$HOME/log"; return 1; }
    echo "PASS: $name"
}
run_case install-over-busy-mac yes --install
run_case automatic-over-busy-mac yes
run_case first-install no --install
