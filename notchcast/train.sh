#!/bin/bash
# One CI run for a train of PRs: merges each PR head onto current main in order (land.sh's merge_onto), pushes the result
# as train/<a>-<b>-<c>, dispatches PR, Proof, Design and Leaks on it and waits. A red train is split in halves, each a
# new train on current main, down to the PR that is red alone; no red train branch is kept. Each green train prints the
# land.sh --train-run line that lands it.
#   notchcast/train.sh <pr> <pr>...
set -euo pipefail
[ "$#" -ge 1 ] && [[ "$*" =~ ^[0-9]+(\ [0-9]+)*$ ]] || { echo 'usage: train.sh <pr> <pr>...' >&2; exit 2; }
repeated=$(printf '%s\n' "$@" | sort | uniq -d | paste -sd' ' -)
[ -z "$repeated" ] || { echo "REFUSED: PR named more than once: $repeated" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"
top=$(pwd)
source notchcast/config.env
source notchcast/merge.sh
refuse() { echo "REFUSED: $*" >&2; exit 1; }
poll=${NOTCHCAST_TRAIN_POLL:-60}
scratch=$(mktemp -d)
cleanup() {
    cd "$top"
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    rm -rf "$scratch"
}
trap cleanup EXIT
tree_at() {
    cd "$top"
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    git worktree add --quiet --detach "$scratch/tree" "$1"
    cd "$scratch/tree"
}
# Merges the PRs $2... onto $1 in order, each a merge commit whose second parent is the PR head, into $tip.
# It runs in this shell, never in $( ), where bash drops set -e and a failed merge step would go unnoticed.
build_train() {
    local pr metadata
    tip=$1
    shift
    for pr in "$@"; do
        metadata=$(gh pr view "$pr" -R "$FORK_REPO" --json state,headRefOid,baseRefName,title,body)
        [ "$(jq -r '.state + " " + .baseRefName' <<< "$metadata")" = 'OPEN main' ] || refuse "#$pr must be open against main"
        head=$(jq -r .headRefOid <<< "$metadata")
        pr_title=$(jq -r '.title // ""' <<< "$metadata")
        pr_body=$(jq -r '.body // ""' <<< "$metadata")
        git -C "$top" fetch -q origin "refs/pull/$pr/head"
        echo "train: #$pr ${head:0:8} onto ${tip:0:8}" >&2
        merge_onto "$tip" >&2
        tip=$(git rev-parse HEAD)
    done
    [ "$(git rev-parse "$tip^{commit}")" = "$tip" ] || refuse "train tip is not a commit: $tip"
}
# Every one must finish green on the train's tip; all but Design take the train's base, as a PR run has it.
workflows='pr.yml proof.yml design.yml leaks.yml'
# Pushes the train of PRs $2... on base $1 as a new branch and dispatches its workflows; sets $branch and $sha.
start_train() {
    local base=$1 file
    shift
    branch="train/$(IFS=-; echo "$*")"
    [ -z "$(git ls-remote origin "refs/heads/$branch")" ] \
        || refuse "origin already has $branch; land it or delete it: git push origin --delete $branch"
    build_train "$base" "$@"
    sha=$tip
    cd "$top"
    git push -q origin "$sha:refs/heads/$branch"
    for file in $workflows; do
        if [ "$file" = design.yml ]; then
            gh workflow run "$file" -R "$FORK_REPO" --ref "$branch" >&2
        else
            gh workflow run "$file" -R "$FORK_REPO" --ref "$branch" -f "base=$base" >&2
        fi
    done
}
# The dispatched run of workflow $1 on branch $2 at $3: pending, none, or its conclusion.
run_verdict() {
    gh run list -R "$FORK_REPO" -w "$1" -b "$2" -e workflow_dispatch -L 20 --json headSha,status,conclusion,createdAt \
        --jq "[.[] | select(.headSha == \"$3\")] | max_by(.createdAt) | if . == null then \"none\" elif .status != \"completed\" then \"pending\" else .conclusion end"
}
# Waits until each workflow on branch $1 at $2 is done; green when all are success. A red one cancels the rest.
wait_train() {
    local branch=$1 sha=$2 file verdict pending waited=0
    while :; do
        pending=
        for file in $workflows; do
            verdict=$(run_verdict "$file" "$branch" "$sha") || verdict=pending
            case "$verdict" in
                success) ;;
                pending) pending=1 ;;
                none) [ "$waited" -lt 900 ] || { echo "train: $file never started on $branch" >&2; return 1; }; pending=1 ;;
                *)
                    echo "train: $file is $verdict on $branch ${sha:0:8}" >&2
                    gh run list -R "$FORK_REPO" -b "$branch" -e workflow_dispatch --json databaseId,status,headSha \
                        --jq ".[] | select(.headSha == \"$sha\" and .status != \"completed\") | .databaseId" |
                        while read -r run; do gh run cancel "$run" -R "$FORK_REPO" >/dev/null || true; done
                    return 1 ;;
            esac
        done
        [ -n "$pending" ] || return 0
        sleep "$poll"
        waited=$((waited + poll))
    done
}
queue=("$*")
status=0
while [ ${#queue[@]} -gt 0 ]; do
    git fetch -q origin main '+refs/notchcast/synced/*:refs/notchcast/synced/*'
    git fetch -q upstream main || refuse 'cannot refresh upstream main'
    base=$(git rev-parse origin/main)
    started=()
    for train in "${queue[@]}"; do
        start_train "$base" $train
        started+=("$branch $sha $train")
    done
    queue=()
    for entry in "${started[@]}"; do
        read -r branch sha train <<< "$entry"
        if wait_train "$branch" "$sha"; then
            echo "GREEN $branch ${sha:0:8} on main ${base:0:8}: notchcast/land.sh --train-run $sha $train"
            continue
        fi
        status=1
        git push -q origin --delete "$branch" || echo "WARN: could not delete $branch" >&2
        set -- $train
        if [ "$#" -eq 1 ]; then
            echo "RED #$1 alone on main ${base:0:8}"
        else
            half=$((($# + 1) / 2))
            echo "RED $branch: splitting into ${*:1:half} | ${*:half+1}"
            queue+=("${*:1:half}" "${*:half+1}")
        fi
    done
done
exit "$status"
