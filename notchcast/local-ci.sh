#!/bin/bash
set -euo pipefail
[[ $# = 1 && $1 =~ ^[0-9]+$ ]] || { echo 'usage: local-ci.sh <pr>' >&2; exit 2; }
PR=$1
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
    if [ "$owned" -eq 1 ]; then rm -rf "$tree" || code=1; fi
    rm -rf "$scratch"
    echo "$state: $description; log: $log"
    # Wake the T3 thread that started the build: build-wake.py only watches Actions runs, so nothing else does.
    if [ -n "${T3CODE_THREAD_ID:-}" ]; then
        echo "build/local $state on #$PR ${head:0:8}: $description; log: $log ... continue." |
            /usr/bin/python3 "$HOME/chad/bin/t3_send.py" "$T3CODE_THREAD_ID" - || true
    fi
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
exec > >(tee "$log") 2>&1
# A tree left by a killed run would make every rerun fail here.
rm -rf "$tree"
# A shared clone, not a worktree: a worktree sees every tag of this checkout, upstream's releases included, and
# upstream's check-migrations.sh then fails on them. The clone gets the fork's tags only, as Actions' checkout does.
git clone --quiet --shared --no-checkout --no-tags "$(git rev-parse --path-format=absolute --git-common-dir)" "$tree"
owned=1
git -C "$tree" remote set-url origin https://github.com/kaczordodgers/notchcast.git
git -C "$tree" fetch --quiet --tags origin "refs/pull/$1/head" "$BASE_SHA" "+refs/heads/main:refs/remotes/origin/main"
main=$(git -C "$tree" rev-parse origin/main)
git -C "$tree" checkout --quiet --detach "$main"
# Build the PR merged onto current main the way land.sh merges it (union drivers, main's generated files,
# xcstrings-union.py for the catalog); any other conflict fails. The status stays on the head.
echo merge > "$scratch/step"
cd "$tree"
git -c core.hooksPath=/dev/null merge --no-commit --no-ff "$head" || true
generated=($(python3 -c 'from notchcast.ci import GENERATED; print(" ".join(GENERATED))'))
git checkout "$main" -- "${generated[@]}"
if git diff --name-only --diff-filter=U | grep -qxF Tinycast/Resources/Localizable.xcstrings; then
    python3 notchcast/xcstrings-union.py --git --main-ref "$main"
fi
unmerged=$(git diff --name-only --diff-filter=U)
[ -z "$unmerged" ] || { echo "merge conflict: $unmerged"; exit 1; }
git -c core.hooksPath=/dev/null -c user.name=Damian -c user.email=336236323+kaczordodgers@users.noreply.github.com \
    commit --quiet --allow-empty --no-edit -m "Merge $head"
export RUNNER_TEMP="$scratch" TMPDIR="$scratch/tmp"
mkdir "$TMPDIR"
python3 "$HOME/chad/bin/build-queue.py" hold -- bash "$tools/notchcast/ci-build.sh"
