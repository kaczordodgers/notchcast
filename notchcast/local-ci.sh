#!/bin/bash
set -euo pipefail
[[ $# = 1 && $1 =~ ^[0-9]+$ ]] || { echo 'usage: local-ci.sh <pr>' >&2; exit 2; }
PR=$1
tools=$(cd "$(dirname "$0")/.." && pwd)
cd "$tools"
source "$tools/notchcast/config.env"
# During a landing hold (notchcast/hold.sh) the owner's build takes the build queue's landing lane, ahead of every
# normal job, and any other PR's local CI waits here until the hold ends.
source "$tools/notchcast/hold.sh"
# Optional machine hooks: NOTCHCAST_BUILD_QUEUE, NOTCHCAST_LOCAL_CI_DIR, notchcast_build_done
# (notchcast/README.md, "Private hooks").
if [ -f "$HOME/.config/notchcast/private.env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.config/notchcast/private.env"
fi
lane=
if hold_turn "$PR"; then lane=--landing; fi
metadata=$(gh pr view "$1" -R "$FORK_REPO" --json headRefOid,baseRefOid)
head=$(jq -r .headRefOid <<< "$metadata")
export HEAD_SHA=$head BASE_SHA=$(jq -r .baseRefOid <<< "$metadata")
root="${NOTCHCAST_LOCAL_CI_DIR:-$HOME/Library/Caches/notchcast/local-ci}"
mkdir -p "$root/logs"
scratch=$(mktemp -d "$root/build.XXXXXX")
tree="$scratch/tree"
log="$scratch/build.log"
stable_log="$root/logs/$head.log"
started=$SECONDS
owned=0
finish() {
    code=$?
    trap - EXIT
    # The build runs inside $tree, which is removed below; a hook can fail from a deleted working directory.
    cd "$root"
    minutes=$(( (SECONDS - started + 59) / 60 ))
    step=$(cat "$scratch/step" 2>/dev/null || echo setup)
    state=failure
    [ "$code" -ne 0 ] || state=success
    description="${minutes}m, $step"
    gh api "repos/${FORK_REPO}/statuses/$head" -f context=build/local \
        -f state="$state" -f description="${description:0:140}" || code=1
    if [ "$code" -eq 0 ]; then
        runs=$(gh run list -R "$FORK_REPO" --workflow PR --commit "$head" \
            --limit 100 --json databaseId,status --jq '.[] | select(.status != "completed") | .databaseId') || code=1
        for run in $runs; do gh run cancel "$run" -R "$FORK_REPO" || code=1; done
    fi
    # The landing lane prints only the build's last 40 lines and keeps the full output in the tree's git dir.
    if [ -n "$lane" ]; then cat "$tree"/.git/land-check/lander/*.log 2>/dev/null || true; fi
    if [ "$owned" -eq 1 ]; then rm -rf "$tree" || code=1; fi
    exec 1>&3 2>&4
    cat "$log"
    cp "$log" "$scratch/published.log" && mv -f "$scratch/published.log" "$stable_log" || code=1
    rm -rf "$scratch"
    log=$stable_log
    echo "$state: $description; log: $log"
    # Tell whoever started the build; nothing else watches a local build.
    if declare -F notchcast_build_done >/dev/null; then
        echo "build/local $state on #$PR ${head:0:8}: $description; log: $log ... continue." |
            notchcast_build_done || true
    fi
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
exec 3>&1 4>&2
exec > "$log" 2>&1
# A shared clone, not a worktree: a worktree sees every tag of this checkout, upstream's releases included, and
# upstream's check-migrations.sh then fails on them. The clone gets the fork's tags only, as Actions' checkout does.
git clone --quiet --shared --no-checkout --no-tags "$(git rev-parse --path-format=absolute --git-common-dir)" "$tree"
owned=1
git -C "$tree" remote set-url origin "https://github.com/$FORK_REPO.git"
git -C "$tree" fetch --quiet --tags origin "refs/pull/$1/head" "$BASE_SHA" "+refs/heads/main:refs/remotes/origin/main"
main=$(git -C "$tree" rev-parse origin/main)
git -C "$tree" checkout --quiet --detach "$main"
# Build the PR merged onto current main the way land.sh merges it (union drivers, main's generated files,
# xcstrings-union.py for the catalog); any other conflict fails. The status stays on the head.
echo merge > "$scratch/step"
cd "$tree"
git -c core.hooksPath=/dev/null merge --no-commit --no-ff "$head" || true
generated=($(python3 -c 'from notchcast.ci import GENERATED; print(" ".join(GENERATED))'))
generated=($(git ls-tree -r --name-only "$main" -- "${generated[@]}"))
[ ${#generated[@]} -eq 0 ] || git checkout "$main" -- "${generated[@]}"
if git diff --name-only --diff-filter=U | grep -qxF Tinycast/Resources/Localizable.xcstrings; then
    python3 notchcast/xcstrings-union.py --git --main-ref "$main"
fi
unmerged=$(git diff --name-only --diff-filter=U)
[ -z "$unmerged" ] || { echo "merge conflict: $unmerged"; exit 1; }
git -c core.hooksPath=/dev/null -c user.name="$MAINTAINER_NAME" -c user.email="$MAINTAINER_EMAIL" \
    commit --quiet --allow-empty --no-edit -m "Merge $head"
echo drift > "$scratch/step"
top="$tree"
source "$tools/notchcast/drift-gates.sh"
run_drift_gates "$main"
export RUNNER_TEMP="$scratch" TMPDIR="$scratch/tmp"
mkdir "$TMPDIR"
if [ -n "${NOTCHCAST_BUILD_QUEUE:-}" ]; then
    # shellcheck disable=SC2086
    $NOTCHCAST_BUILD_QUEUE hold $lane -- bash "$tools/notchcast/ci-build.sh"
else
    bash "$tools/notchcast/ci-build.sh"
fi
