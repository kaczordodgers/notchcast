#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export WORK HOME="$WORK/home" NOTCHCAST_RUNNER_ROOT="$WORK/root"
mkdir -p "$HOME" "$WORK/root/mba-1" "$WORK/root/mba-2" "$WORK/loaded" "$WORK/busy"
touch "$WORK/root/mba-1/.runner" "$WORK/root/mba-2/.runner" "$WORK/loaded/mba-1" "$WORK/loaded/mba-2" "$WORK/busy/mba-2"
launchctl() {
    local name=${2##*notchcast.runner.}
    name=${name%.plist}
    [ "$1" = bootstrap ] && name=${3##*notchcast.runner.} && name=${name%.plist}
    case "$1" in
        print) [ -e "$WORK/loaded/$name" ] ;;
        bootout) rm "$WORK/loaded/$name"; echo "bootout $name" >> "$WORK/calls" ;;
        bootstrap) touch "$WORK/loaded/$name"; echo "bootstrap $name" >> "$WORK/calls" ;;
    esac
}
pgrep() { local name=${2%/bin/Runner.Worker}; [ -e "$WORK/busy/${name##*/}" ]; }
gh() { echo "$3 ${7% *}" >> "$WORK/calls"; }
export -f launchctl pgrep gh
gate() { : > "$WORK/calls"; bash "$HERE/gate.sh" mba owner/repo > "$WORK/log"; }
calls() { [ "$(paste -sd, "$WORK/calls")" = "$1" ] || { echo "FAIL: $2: $(paste -sd, "$WORK/calls")"; cat "$WORK/log"; exit 1; }; }

gate
calls 'NOTCHCAST_IDLE_MBA 1' 'one of two runners idle'
gate
calls '' 'unchanged count published again'
echo 'PASS: idle count published once, the busy runner not counted'

printf '#!/bin/bash\nexit 1\n' > "$WORK/root/admit"
chmod 755 "$WORK/root/admit"
gate
calls 'NOTCHCAST_IDLE_MBA 0' 'first refusal'
gate
calls 'bootout mba-1' 'second refusal'
test -e "$WORK/loaded/mba-2"
echo 'PASS: a refusal publishes 0 first, then stops only the runner without a job'

rm "$WORK/root/admit" "$WORK/busy/mba-2"
gate
calls 'bootstrap mba-1,NOTCHCAST_IDLE_MBA 2' 'admitted again'
echo 'PASS: an admitted Mac starts its runner again'
