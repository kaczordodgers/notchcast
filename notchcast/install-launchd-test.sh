#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home with space"
mkdir -p "$HOME" "$WORK/origin/notchcast"
git init -q -b main "$WORK/origin"
git -C "$WORK/origin" config user.name Fixture
git -C "$WORK/origin" config user.email fixture@example.invalid
cp "$HERE/install-launchd.sh" "$HERE/config.env" "$WORK/origin/notchcast/"
printf '#!/bin/bash\necho old\n' > "$WORK/origin/notchcast/update.sh"
git -C "$WORK/origin" add .
git -C "$WORK/origin" commit -qm initial
git clone -q "$WORK/origin" "$WORK/checkout"
launchctl() { :; }
export -f launchctl
bash "$WORK/checkout/notchcast/install-launchd.sh" update --auto-install
WRAPPER="$HOME/Library/Application Support/notchcast/jobs/Notchcast update"
bash "$WORK/checkout/notchcast/install-launchd.sh" kick
for label in update kick; do
    plist="$HOME/Library/LaunchAgents/notchcast.$label.plist"
    exe=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist")
    test -x "$exe"
    test "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$plist" 2>/dev/null || true)" = ''
    bash -n "$exe"
done
grep -qF kick.sh "$HOME/Library/Application Support/notchcast/jobs/Notchcast sync check"
git -C "$WORK/origin" checkout -q --orphan rewritten
printf '#!/bin/bash\nHERE="$(cd "$(dirname "$0")" && pwd)"\nsource "$HERE/config.env"\ntest -f "$HERE/install-app.sh"\necho "rewritten $APP_NAME $*"\n' > "$WORK/origin/notchcast/update.sh"
cp "$HERE/install-app.sh" "$WORK/origin/notchcast/"
git -C "$WORK/origin" add .
git -C "$WORK/origin" commit -qm rewritten
git -C "$WORK/origin" branch -M main
HEAD_BEFORE="$(git -C "$WORK/checkout" rev-parse HEAD)"
printf '# dirty\n' >> "$WORK/checkout/notchcast/config.env"
check() {
    bash "$WRAPPER" > "$WORK/log" 2>&1
    cat "$WORK/log"
    grep -qx 'rewritten Notchcast --install' "$WORK/log" || { echo 'FAIL: rewritten main tooling not run'; exit 1; }
    test "$(git -C "$WORK/checkout" rev-parse HEAD)" = "$HEAD_BEFORE"
    test "$(tail -1 "$WORK/checkout/notchcast/config.env")" = '# dirty'
}
check
echo 'PASS: rewritten main, arguments, adjacent files and untouched checkout'
TOOLS="$HOME/Library/Application Support/notchcast/tools"
OLD_COPY="$(readlink "$TOOLS")"
printf '\necho v2\n' >> "$WORK/origin/notchcast/update.sh"
git -C "$WORK/origin" add .
git -C "$WORK/origin" commit -qm v2
check
NEW_COPY="$(readlink "$TOOLS")"
test "$NEW_COPY" != "$OLD_COPY"
test -f "$NEW_COPY/update.sh"
test ! -e "${OLD_COPY%/notchcast}"
grep -qx v2 "$WORK/log"
test "$(git -C "$WORK/checkout" rev-parse refs/remotes/origin/main)" = "$(git -C "$WORK/origin" rev-parse main)"
echo 'PASS: consecutive refresh swaps link, removes old copy and runs v2'
mv "$WORK/origin" "$WORK/unreachable"
check
test "$(grep -c 'refresh failed' "$WORK/log")" = 1
echo 'PASS: unreachable origin uses last extracted copy'
rm "$HOME/Library/Application Support/notchcast/tools"
bash "$WRAPPER" > "$WORK/log" 2>&1
grep -qx old "$WORK/log"
test "$(grep -c 'refresh failed' "$WORK/log")" = 1
echo 'PASS: cold offline run uses checkout'
mv "$WORK/unreachable" "$WORK/origin"
bash "$WORK/checkout/notchcast/install-launchd.sh" update
bash "$WRAPPER" > "$WORK/log" 2>&1
grep -qx 'rewritten Notchcast ' "$WORK/log"
git -C "$WORK/origin" rm -q notchcast/install-app.sh
git -C "$WORK/origin" commit -qm incomplete
bash "$WRAPPER" > "$WORK/log" 2>&1
grep -qx 'rewritten Notchcast ' "$WORK/log"
test "$(grep -c 'refresh failed' "$WORK/log")" = 1
echo 'PASS: incomplete extraction preserves last copy; no extra arguments'
