#!/bin/bash
set -euo pipefail
[[ $# = 1 && $1 =~ ^[0-9]+$ ]] || { echo 'usage: local-ci.sh <pr>' >&2; exit 2; }
tools=$(cd "$(dirname "$0")/.." && pwd)
cd "$tools"
metadata=$(gh pr view "$1" -R kaczordodgers/notchcast --json headRefOid,baseRefOid)
head=$(jq -r .headRefOid <<< "$metadata")
export HEAD_SHA=$head BASE_SHA=$(jq -r .baseRefOid <<< "$metadata")
root="$HOME/agents/nc-local-ci"
mkdir -p "$root/logs"
scratch=$(mktemp -d "$root/build.XXXXXX")
tree="$root/$head"
log="$root/logs/$head.log"
started=$SECONDS
owned=0
finish() {
    code=$?
    trap - EXIT
    minutes=$(( (SECONDS - started + 59) / 60 ))
    step=$(cat "$scratch/step" 2>/dev/null || echo setup)
    state=failure
    [ "$code" -ne 0 ] || state=success
    description="$(hostname -s): ${minutes}m, $step"
    gh api "repos/kaczordodgers/notchcast/statuses/$head" -f context=build/local \
        -f state="$state" -f description="${description:0:140}" || code=1
    if [ "$code" -eq 0 ]; then
        runs=$(gh run list -R kaczordodgers/notchcast --workflow PR --commit "$head" \
            --limit 100 --json databaseId,status --jq '.[] | select(.status != "completed") | .databaseId') || code=1
        for run in $runs; do gh run cancel "$run" -R kaczordodgers/notchcast || code=1; done
    fi
    if [ "$owned" -eq 1 ]; then git worktree remove --force "$tree" || code=1; fi
    rm -rf "$scratch"
    echo "$state: $description; log: $log"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
exec > >(tee "$log") 2>&1
git fetch origin "refs/pull/$1/head" "$BASE_SHA"
git worktree add --detach "$tree" "$head"
owned=1
export RUNNER_TEMP="$scratch" TMPDIR="$scratch/tmp"
mkdir "$TMPDIR"
cd "$tree"
python3 "$HOME/chad/bin/build-queue.py" hold -- bash "$tools/notchcast/ci-build.sh"
