#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${NOTCHCAST_SCRATCH:-$HOME/Library/Caches/notchcast}/install-test"
mkdir -p "$ROOT"
WORK="$(mktemp -d "$ROOT/run.XXXXXX")"
export NOTCHCAST_APP="$WORK/Installed.app"
export NOTCHCAST_AGENT=notchcast.test.app
export NOTCHCAST_WATCH_SECONDS=8
export NOTCHCAST_TRASH="$WORK/Trash"
AGENT="gui/$(id -u)/$NOTCHCAST_AGENT"
PLIST="$WORK/agent.plist"
cleanup() {
    launchctl bootout "$AGENT" 2>/dev/null || true
    rm -f "$PLIST"
}
trap cleanup EXIT
if launchctl print "$AGENT" >/dev/null 2>&1; then
    echo 'scratch agent already loaded; refusing to replace it'
    trap - EXIT
    exit 1
fi
bundle() {
    local path="$WORK/$1.app"
    mkdir -p "$path/Contents/MacOS"
    printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>test-app</string><key>CFBundleShortVersionString</key>' "<string>$2</string></dict></plist>" > "$path/Contents/Info.plist"
    printf '#!/bin/bash\n%s\n' "$3" > "$path/Contents/MacOS/test-app"
    chmod +x "$path/Contents/MacOS/test-app"
}
bundle Good 1.0.0 'exec /bin/sleep 600'
bundle Bad 2.0.0 'exit 1'
bundle Quitter 0.9.0 'exit 0'
# The keys install-launchd.sh gives the real agent, ThrottleInterval included.
cat > "$PLIST" <<PLIST
<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>$NOTCHCAST_AGENT</string>
<key>ProgramArguments</key><array><string>$NOTCHCAST_APP/Contents/MacOS/test-app</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>10</integer></dict></plist>
PLIST
# A healthy build over an old one in a quit loop must stay: kickstart waits out the throttle.
ditto "$WORK/Quitter.app" "$NOTCHCAST_APP"
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 3
"$HERE/install-app.sh" "$WORK/Good.app" | tee "$WORK/good.log"
grep -q '^left running: 1.0.0 (new)$' "$WORK/good.log"
STATUS=0
"$HERE/install-app.sh" "$WORK/Bad.app" > "$WORK/bad.log" 2>&1 || STATUS=$?
cat "$WORK/bad.log"
[ "$STATUS" -ne 0 ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$NOTCHCAST_APP/Contents/Info.plist")" = 1.0.0 ]
cmp "$WORK/Good.app/Contents/MacOS/test-app" "$NOTCHCAST_APP/Contents/MacOS/test-app"
launchctl print "$AGENT" | grep -q 'state = running'
grep -q '^left running: 1.0.0 (previous)$' "$WORK/bad.log"
echo "PASS: good restored, scratch agent running, failed install exit=$STATUS"
