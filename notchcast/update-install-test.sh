#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$HERE/update.sh" "$HERE/config.env" "$WORK/"
printf '#!/bin/bash\ntouch "$HOME/installed"\n' > "$WORK/install-app.sh"
chmod +x "$WORK/install-app.sh"
mkdir -p "$WORK/Fixture.app/Contents"
printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>app.notchcast</string><key>CFBundleShortVersionString</key><string>0.12.8.snapshot.20261107210745</string></dict></plist>' > "$WORK/Fixture.app/Contents/Info.plist"
export FIXTURE="$WORK/Fixture.app"
MIXED_TAGS=$'v0.12.8.snapshot.20261107210745\nv0.12.10-beta.135\nv0.12.8.snapshot.20261107201744\nv0.12.8'
LATEST=v0.12.8.snapshot.20261107210745
export RELEASE_TAGS="$MIXED_TAGS"
gh() {
    case "$1 $2" in
        'release list')
            local limit=30
            while [ "$1" != --jq ]; do
                case "$1" in
                    -L) limit=$2; shift 2 ;;
                    *) shift ;;
                esac
            done
            printf '%s\n' "$RELEASE_TAGS" | jq -Rn --argjson limit "$limit" '[inputs | {tagName: ., isDraft: false}] | .[:$limit]' | jq -r "$2"
            ;;
        'release download') printf '%s\n' "$3" > "$HOME/downloaded" ;;
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
    local name=$1 installed=$2 expected=$3
    shift 3
    export HOME="$WORK/$name" NOTCHCAST_APP="$WORK/$name/App.app"
    mkdir -p "$HOME"
    if [ "$installed" != no ]; then
        cp -R "$FIXTURE" "$NOTCHCAST_APP"
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $installed" "$NOTCHCAST_APP/Contents/Info.plist"
    fi
    if [ "$expected" != none ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${expected#v}" "$FIXTURE/Contents/Info.plist"
    fi
    bash "$WORK/update.sh" "$@" > "$HOME/log" 2>&1 || { cat "$HOME/log"; return 1; }
    if [ "$expected" = none ]; then
        test ! -f "$HOME/downloaded" || { echo "FAIL: $name downloaded a release"; return 1; }
        test ! -f "$HOME/installed" || { echo "FAIL: $name installed a release"; return 1; }
    else
        test -f "$HOME/downloaded" || { echo "FAIL: $name did not download"; return 1; }
        grep -qxF "$expected" "$HOME/downloaded" || { echo "FAIL: $name downloaded the wrong tag"; cat "$HOME/downloaded"; return 1; }
        test -f "$HOME/installed" || { echo "FAIL: $name did not install"; cat "$HOME/log"; return 1; }
    fi
    test ! -f "$HOME/idle-read" || { echo "FAIL: $name read idle time"; return 1; }
    test ! -f "$HOME/slept" || { echo "FAIL: $name waited"; return 1; }
    ! grep -qiE 'idle|in use|next run' "$HOME/log" || { echo "FAIL: $name deferred"; cat "$HOME/log"; return 1; }
    echo "PASS: $name"
}
run_case install-over-busy-mac 0.12.7 "$LATEST" --install
run_case automatic-over-busy-mac 0.12.7 "$LATEST"
run_case first-install no "$LATEST" --install
run_case older-snapshot 0.12.8.snapshot.20261107201744 "$LATEST"
run_case installed-beta 0.12.10-beta.135 "$LATEST"
run_case same-snapshot "${LATEST#v}" none
run_case installed-newer-snapshot 0.12.8.snapshot.20261108000000 none
export RELEASE_TAGS=$'manual.snapshot.20261108000000\n0.12.8.snapshot.20261108000000\nv0.12.8.snapshot.20261107210745'
run_case malformed-snapshot-tags 0.12.8.snapshot.20261107201744 "$LATEST"
export RELEASE_TAGS=$'v0.12.10-beta.135\nv0.12.8'
run_case mirrors-only 0.12.8.snapshot.20261107201744 none
export RELEASE_TAGS="$MIXED_TAGS"$'\nv0.12.7-beta.1.snapshot.20261108000000'
run_case lower-base-newer-snapshot "${LATEST#v}" v0.12.7-beta.1.snapshot.20261108000000
printf -v RELEASE_TAGS 'v0.12.10-beta.%s\n' {1..30}
RELEASE_TAGS+="$LATEST"
run_case snapshot-after-30-mirrors 0.12.8.snapshot.20261107201744 "$LATEST"
