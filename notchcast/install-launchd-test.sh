#!/bin/bash
# Installs the update and kick agents into a scratch home with launchctl stubbed; no real agent is touched.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/home with space"
printf '#!/bin/bash\nexit 0\n' > "$scratch/bin/launchctl"
chmod 755 "$scratch/bin/launchctl"
run() { HOME="$scratch/home with space" PATH="$scratch/bin:$PATH" "$here/install-launchd.sh" "$@" > /dev/null; }
run update --auto-install
run kick
check() { # label name script
    local plist="$scratch/home with space/Library/LaunchAgents/$1.plist" exe
    [ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$plist" 2>/dev/null || true)" = "" ]
    exe=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist")
    [ "$(basename "$exe")" = "$2" ]
    [ -x "$exe" ]
    /bin/bash -n "$exe"
    grep -qF "$3" "$exe"
}
check notchcast.update 'Notchcast update' update.sh
check notchcast.kick 'Notchcast sync check' kick.sh
grep -q -- '--install' "$scratch/home with space/Library/Application Support/notchcast/jobs/Notchcast update"
echo 'PASS: install-launchd-test.sh'
