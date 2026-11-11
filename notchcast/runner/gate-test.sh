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
grep -q 'idle 1$' "$WORK/log"
gate
calls 'NOTCHCAST_IDLE_MBA 1' 'the next minute'
test ! -s "$WORK/log"
echo 'PASS: idle count published every run and logged once, the busy runner not counted'

printf '#!/bin/bash\nexit 1\n' > "$WORK/root/admit"
chmod 755 "$WORK/root/admit"
gate
calls 'NOTCHCAST_IDLE_MBA -1' 'first refusal'
gate
calls 'bootout mba-1,NOTCHCAST_IDLE_MBA -1' 'second refusal'
test -e "$WORK/loaded/mba-2"
echo 'PASS: a refusal publishes -1 first, then stops only the runner without a job'

rm "$WORK/root/admit" "$WORK/busy/mba-2"
gate
calls 'bootstrap mba-1,NOTCHCAST_IDLE_MBA 2' 'admitted again'
rm "$WORK/loaded/mba-1"
gate
calls 'NOTCHCAST_IDLE_MBA 1' 'booted out by hand'
echo 'PASS: an admitted Mac starts again the runner the gate stopped, and no other'

# The hook beside a stand-in gate.sh, which records that the hook reached it, and a kill that records its target.
kill() { echo "kill $*" >> "$WORK/calls"; }
export -f kill
mkdir -p "$WORK/hook" "$HOME/Library/Logs/notchcast"
cp "$HERE/job-started.sh" "$WORK/hook/"
printf '#!/bin/bash\necho "gate $*" >> "$WORK/calls"\n' > "$WORK/hook/gate.sh"
echo '{"pull_request": {"head": {"repo": {"full_name": "owner/repo"}}}}' > "$WORK/own.json"
echo '{"pull_request": {"head": {"repo": {"full_name": "fork/repo"}}}}' > "$WORK/fork.json"
echo '{"ref": "refs/heads/branch"}' > "$WORK/push.json"
hook() { # event payload actor repository
    : > "$WORK/calls"
    NOTCHCAST_RUNNER_GATE='mba owner/repo' GITHUB_EVENT_NAME=$1 GITHUB_EVENT_PATH="$WORK/$2" GITHUB_ACTOR=${3:-owner} \
        GITHUB_REPOSITORY=${4:-owner/repo} bash -e "$WORK/hook/job-started.sh" 2> "$WORK/log"
}
admitted() {
    hook "$@" || { echo "FAIL: refused $*"; cat "$WORK/log"; exit 1; }
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/calls" ] && break; sleep 0.5; done
    calls 'gate mba owner/repo' "admitted $*"
}
refused() {
    if hook "$@"; then echo "FAIL: admitted $*"; exit 1; fi
    grep -q 'refused' "$WORK/log"
    calls "kill -9 $$" "refused $*"
}
admitted push push.json
admitted workflow_dispatch push.json
admitted pull_request own.json
echo "PASS: the hook admits the owner's push, dispatch and own-branch pull request"

refused push push.json someone
refused pull_request fork.json
refused pull_request push.json
refused push missing.json
refused pull_request_target own.json
refused push push.json owner other/repo
if NOTCHCAST_RUNNER_GATE='mba owner/repo' bash -e "$WORK/hook/job-started.sh" 2> "$WORK/log"; then echo 'FAIL: admitted no data'; exit 1; fi
echo 'PASS: the hook refuses another actor, a fork head, a missing event file and any other event, and kills its parent'
