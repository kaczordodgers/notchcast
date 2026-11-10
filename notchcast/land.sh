#!/bin/bash
set -euo pipefail
# A stale checkout lands by stale rules (one skipped the Sync wait), so a landing always runs main's tooling.
if [ "$#" -ge 1 ] && [ "$1" != --check ] && [ -z "${NOTCHCAST_LAND_TOOLS:-}" ]; then
    origin_top=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
    git -C "$origin_top" fetch --quiet origin main || { echo 'REFUSED: could not fetch origin main' >&2; exit 1; }
    if [ "$(git -C "$origin_top" rev-parse HEAD:notchcast)" != "$(git -C "$origin_top" rev-parse origin/main:notchcast)" ] \
        || ! git -C "$origin_top" diff --quiet HEAD -- notchcast; then
        tools=$(mktemp -d)
        git -C "$origin_top" worktree add --quiet --detach "$tools/tree" origin/main
        echo "land.sh: this checkout's notchcast/ differs from origin/main; running main's copy"
        cd "$tools/tree"
        NOTCHCAST_LAND_TOOLS=$tools NOTCHCAST_LAND_ORIGIN=$origin_top exec bash notchcast/land.sh "$@"
    fi
fi
remove_tools() {
    [ -z "${hold_claimed:-}" ] || hold_release_claimed  # both EXIT traps run this
    [ -n "${NOTCHCAST_LAND_ORIGIN:-}" ] || return 0
    cd "$NOTCHCAST_LAND_ORIGIN"
    git worktree remove --force "$NOTCHCAST_LAND_TOOLS/tree" >/dev/null 2>&1 || true
    rm -rf "$NOTCHCAST_LAND_TOOLS"
}
trap remove_tools EXIT
trap 'exit 1' HUP INT TERM
source "$(dirname "$0")/local-build-status.sh"
selector="$(cd "$(dirname "$0")" && pwd)/changed-harnesses.sh"
cd "$(git rev-parse --show-toplevel)"
source "$(dirname "$0")/merge.sh"
delete_head() {
    local name=$1 expected=$2 fork=${3:-false} remote local_head
    [ "$fork" = false ] || return 0
    remote=$(git ls-remote origin "refs/heads/$name") || { echo 'WARN: cannot read origin head' >&2; return 0; }
    if [ "${remote%%[[:space:]]*}" = "$expected" ]; then
        git push origin --delete "$name" || echo "WARN: could not delete origin/$name" >&2
    fi
    local_head=$(git rev-parse --verify "refs/heads/$name" 2>/dev/null) || return 0
    if [ "$local_head" = "$expected" ]; then
        git branch -D -- "$name" || echo "WARN: could not delete local $name (possibly checked out)" >&2
    fi
    return 0
}
source "$(dirname "$0")/sync-wait.sh"
source "$(dirname "$0")/hold.sh"
refresh_upstream() {
    git fetch -q upstream main || refuse 'cannot refresh upstream main'
}
drift_report() {
    local base=$1 commit=$2
    # Seed from main so a crossing this landing adds is filed, not absorbed as already known.
    if [ ! -f "$HOME/Library/Caches/notchcast/drift-alerts.json" ] && git switch --quiet --detach "$base"; then
        python3 "$drift_tools/check-drift.py" --root "$PWD" --report >/dev/null || echo 'WARN: drift alerts not seeded from main' >&2
    fi
    if git switch --quiet --detach "$commit"; then
        python3 "$drift_tools/check-drift.py" --root "$PWD" --report || echo 'WARN: drift report failed after landing' >&2
    else
        echo 'WARN: drift report could not read the landed commit' >&2
    fi
}
squash_message() {
    local title=$pr_title
    [[ "$title" == Notchcast:* ]] || title="Notchcast: $title"
    printf '%s (#%s)\n' "$title" "$pr"
    if printf '%s\n' "$title" | grep -Eiq '^(notchcast: )?fix '; then
        printf '\n'
        grep -E '^No test: [^[:space:]].*' <<< "$pr_body" || true
    fi
    if [ -n "$drift_signoff" ]; then printf '\n%s\n' "$drift_signoff"; fi
}
# Runs "$@" in a subshell with errexit on, so its refuse ends one PR, not the run; leaves the exit code in status.
attempt() {
    set +e
    (set -e; "$@")
    status=$?
    set -e
}
# Takes PR $1 off the train; $2 says why unless the refusal above did. The last PR's reason is the run's refusal.
drop() {
    local pr kept=()
    if [ ${#train[@]} -eq 1 ]; then
        [ -z "${2:-}" ] || refuse "$2"
        exit 1
    fi
    echo "DROPPED #$1: ${2:-refused above}; the train goes on without it" >&2
    for pr in "${train[@]}"; do
        [ "$pr" = "$1" ] || kept+=("$pr")
    done
    train=("${kept[@]}")
    rerun=1
}
# Check runs on the commit, not the PR's statusCheckRollup: the rollup omits dispatched runs, and a PR
# GitHub calls conflicting gets no pull_request run at all. The newest run wins over a cancelled one.
check_run() {
    gh api "repos/$FORK_REPO/commits/$1/check-runs?check_name=$2&filter=all" \
        --jq '[.check_runs[] | select(.app.slug == "github-actions")] | max_by(.started_at) | if . == null then "none" elif .status != "completed" then "pending" else .conclusion end'
}
green() { [ "$(check_run "$1" build)" = success ] || local_build_green "$1"; }
# The gates PR $1 passes before it is merged: open, ready, and its checks green on its exact head.
admit() {
    local pr=$1 metadata head name verdict required branch generated proven sha
    metadata=$(gh pr view "$pr" -R "$FORK_REPO" --json state,isDraft,headRefOid,headRefName,baseRefName,isCrossRepository,title,body)
    [ "$(jq -r .baseRefName <<< "$metadata")" = main ] || refuse 'PR base must be main'
    head=$(python3 -c 'import json,sys; p=json.load(sys.stdin); assert p["state"] == "OPEN" and not p["isDraft"], "PR must be open and ready"; print(p["headRefOid"])' <<< "$metadata") || refuse 'PR must be open and ready'
    git fetch origin main "refs/pull/$pr/head" '+refs/notchcast/synced/*:refs/notchcast/synced/*'
    git cat-file -e "$head^{commit}" || refuse 'PR head unavailable'
    for name in design leaks; do
        verdict=$(check_run "$head" "$name")
        [ "$verdict" = none ] || [ "$verdict" = success ] || refuse "$name is $verdict on ${head:0:8}; wait for success"
    done
    branch=$(jq -r .headRefName <<< "$metadata")
    required=$(python3 notchcast/app-proof.py plan origin/main "$head")
    if [ -n "$required" ]; then
        verdict=$(check_run "$head" proof)
        [ "$verdict" = success ] || refuse "real-app proof ($required) is $verdict on ${head:0:8}; it runs on the PR, or: gh workflow run Proof --ref $branch -R $FORK_REPO"
    fi
    verdict=$(check_run "$head" build)
    if local_build_green "$head"; then verdict=success; fi
    [ "$verdict" = success ] || [ "$verdict" = none ] || [ "$verdict" = cancelled ] \
        || refuse "build is $verdict on ${head:0:8}: wait for it or fix it (cancel a pending one to use a green head that differs only in generated files)"
    if [ "$verdict" != success ]; then
        # A head that differs from a green head of this branch only in generated files needs no new build:
        # landing keeps main's copies of them (merge_onto), so the green build already proved what lands.
        generated=$(python3 -c 'from notchcast.ci import GENERATED; print("\n".join(GENERATED))')
        proven=
        for sha in $(git rev-list --max-count=30 "$head") $(gh run list -R "$FORK_REPO" -w PR -b "$branch" -L 30 --json headSha,conclusion \
                --jq '.[] | select(.conclusion == "success") | .headSha' | awk '!seen[$0]++'); do
            git fetch -q origin "$sha" 2>/dev/null && green "$sha" || continue
            [ -n "$(git diff --name-only "$sha" "$head" | grep -vxF "$generated")" ] || { proven=$sha; break; }
        done
        [ -n "$proven" ] || refuse "build is not green on ${head:0:8}; if it has none, run: gh workflow run PR --ref $branch -R $FORK_REPO"
        echo "build: ${head:0:8} differs from green ${proven:0:8} only in generated files"
    fi
    printf '%s\n' "$metadata" > "$scratch/pr-$pr.json"
}
# Sets the globals merge_onto and squash_message read from what admit (or --check) saved for PR $1.
load() {
    pr=$1
    metadata=$(< "$scratch/pr-$pr.json")
    head=$(jq -r .headRefOid <<< "$metadata")
    pr_title=$(jq -r '.title // ""' <<< "$metadata")
    pr_body=$(jq -r '.body // ""' <<< "$metadata")
}
# A fresh scratch tree at commit $1, with the shell in it.
tree_at() {
    cd "$top"
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    git worktree add --quiet --detach "$scratch/tree" "$1"
    cd "$scratch/tree"
}
top=$(pwd)
scratch=$(mktemp -d)
cleanup() {
    local code=$?
    cd "$top"  # out of the scratch tree before it goes
    git worktree remove --force "$scratch/base" >/dev/null 2>&1 || true
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    rm -rf "$scratch"
    remove_tools
    # Bash 3.2 runs this with status 0 after an unbound-variable abort, so only a finished run exits 0.
    [ "$code" -ne 0 ] || [ -n "${finished:-}" ] || code=1
    exit "$code"
}
trap cleanup EXIT
mkdir "$scratch/tmp"
check=0
if [ "${1:-}" = --check ] && [ "$#" -eq 3 ]; then
    check=1
    base=$(git rev-parse --verify "$2^{commit}")
    head=$(git rev-parse --verify "$3^{commit}")
    # The head commit stands in for the PR.
    jq -n --arg head "$head" --arg title "$(git show -s --format=%s "$head")" --arg body "$(git show -s --format=%b "$head")" \
        '{headRefOid: $head, title: $title, body: $body}' > "$scratch/pr-check.json"
    train=(check)
elif [ "$#" -ge 1 ] && [[ "$*" =~ ^[0-9]+(\ [0-9]+)*$ ]]; then
    repeated=$(printf '%s\n' "$@" | sort | uniq -d | paste -sd' ' -)
    [ -z "$repeated" ] || refuse "PR named more than once: $repeated"
    hold_claim "$@"
    train=("$@")
    if [ -n "$hold_pr" ] && [ "$#" -gt 1 ]; then
        echo "landing is held for #$hold_pr: the train is cut to it" >&2
        train=("$hold_pr")
    fi
    hold_owner=${hold_pr:-$1}
    for pr in "${train[@]}"; do
        attempt admit "$pr"
        [ "$status" -eq 0 ] || drop "$pr"
    done
    base=$(git rev-parse origin/main)
else
    refuse 'usage: land.sh <pr>... | --check <base-ref> <head-ref>'
fi
# Squash here, not on GitHub: GitHub ignores .gitattributes merge=union and calls union-only overlaps conflicts.
# Merges PR $2 onto $1 and leaves its squash commit, whose only parent is $1, in $scratch/commit-$2.
squash_onto() {
    load "$2"
    merge_onto "$1"
    squash_message > "$scratch/message"
    [ "$check" -eq 1 ] || notchcast/check-identity.sh message "$scratch/message" || refuse 'commit message names something private'
    GIT_AUTHOR_NAME="$MAINTAINER_NAME" GIT_AUTHOR_EMAIL="$MAINTAINER_EMAIL" \
        GIT_COMMITTER_NAME="$MAINTAINER_NAME" GIT_COMMITTER_EMAIL="$MAINTAINER_EMAIL" \
        git commit-tree "HEAD^{tree}" -p "$1" -F "$scratch/message" > "$scratch/commit-$2"
}
# Stacks the train on $base, each PR squashed onto the one before it; a PR that refuses is dropped. Checks out tip.
build_chain() {
    local pr
    cd "$top"
    refresh_upstream
    tip=$base
    for pr in "${train[@]}"; do
        [ ${#train[@]} -eq 1 ] || echo "train: #$pr onto ${tip:0:8}"
        attempt squash_onto "$tip" "$pr"
        if [ "$status" -eq 0 ]; then tip=$(< "$scratch/commit-$pr"); else drop "$pr"; fi
    done
    tree_at "$tip"
}
# Upstream's runner takes one name; the hook ci-tests.sh uses makes it run "$@" in one parallel pass. Sets failed.
run_harnesses() {
    local name file status=0
    failed=
    [ "$#" -gt 0 ] || return 0
    rm -rf "$scratch/tmp"
    mkdir "$scratch/tmp"
    grep -q '^    local name=\$1$' Scripts/run-tests.sh || refuse 'run-tests.sh changed shape; update the list hook in land.sh'
    sed -i '' -E 's/^    local name=\$1$/    local name=$1; case " $NOTCHCAST_ONLY_TESTS " in *" $name "*) ;; *) return 0;; esac/' Scripts/run-tests.sh
    NOTCHCAST_ONLY_TESTS="$*" TMPDIR="$scratch/tmp" TINYCAST_TEST_JOBS="${CHAD_BUILD_QUEUE_JOBS:-4}" ./Scripts/run-tests.sh || status=$?
    git checkout -q -- Scripts/run-tests.sh
    for name in "$@"; do
        [ -e "$(echo "$scratch"/tmp/tinycast-harness*/"$name.log")" ] || refuse "$name is selected but run-tests.sh does not run it"
    done
    for file in "$scratch"/tmp/tinycast-harness*/*.failed; do
        [ ! -e "$file" ] || failed="$failed${failed:+ }$(basename "$file" .failed)"
    done
    [ "$status" -eq 0 ] || [ -n "$failed" ] || refuse 'the harness run failed without naming a harness'
}
# One pass on the tree at HEAD over the union of what each squash in $base..HEAD selects. Sets failed.
# Not covered without an Xcode build of this tree: code no selected harness compiles (UI, AppCore wiring,
# resources); the PR build covered each head alone, and Sync and Snapshot follow on main.
harnesses() {
    local commit proof names
    for commit in $(git rev-list --reverse "$base..HEAD"); do
        TMPDIR="$scratch/tmp" "$selector" "$commit^" "$commit"
    done | sort -u > "$scratch/selected"
    [ -s "$scratch/selected" ] || refuse 'no harness selected for the merged tree'
    names=$(< "$scratch/selected")
    # A green PR build of exactly this tree (ci.py tested-key) ran every harness the hosted runner can.
    if [ "$check" -eq 0 ] && proof=$(python3 "$(dirname "$selector")/ci.py" tested-run HEAD) && [ -n "$proof" ]; then
        echo "harnesses: $proof built and tested this tree; running only what its runner skips"
        names=$(grep -xF -f <(tr ' ' '\n' <<< "$CI_SKIP_TESTS") "$scratch/selected" || true)
    fi
    run_harnesses $names
}
# Runs those of the harnesses $2 that exist at commit $1 on its tree. Sets failed.
harnesses_at() {
    local name names=
    tree_at "$1"
    for name in $2; do
        [ ! -e "Tests/$name.swift" ] || names="$names $name"
    done
    run_harnesses $names
}
# Sets breaker to the first PR whose squash turns the harnesses $1 red, by halving; refuses if main is red too.
breaking_pr() {
    local low=0 high=$((${#train[@]} - 1)) mid
    while [ "$low" -lt "$high" ]; do
        mid=$(((low + high) / 2))
        echo "bisecting: $1 on the train up to #${train[$mid]}"
        harnesses_at "$(< "$scratch/commit-${train[$mid]}")" "$1"
        if [ -n "$failed" ]; then high=$mid; else low=$((mid + 1)); fi
    done
    breaker=${train[$low]}
    [ "$low" -eq 0 ] || return 0
    echo "bisecting: $1 on main ${base:0:8}"
    harnesses_at "$base" "$1"
    [ -z "$failed" ] || refuse "main is red: $failed"
}
rerun=1
pushes=0
while :; do
    build_chain
    if [ "$rerun" -eq 1 ]; then
        harnesses
        if [ -n "$failed" ]; then
            red=$failed
            breaking_pr "$red"
            drop "$breaker" "$red failed"
            continue
        fi
        echo 'PASS: merged-tree harnesses'
        rerun=0
    fi
    [ "$check" -eq 0 ] || { finished=1; exit 0; }
    wait_for_sync
    for pr in "${train[@]}"; do
        load "$pr"
        [ "$(gh pr view "$pr" -R "$FORK_REPO" --json headRefOid --jq .headRefOid)" = "$head" ] \
            || drop "$pr" "PR #$pr moved past ${head:0:8} during the check; run land.sh $pr again"
    done
    [ "$rerun" -eq 0 ] || continue
    hold_renew_claimed
    check_hold "$hold_owner"  # a hold set while the harnesses ran wins
    # The chain's first parent is $base, so this plain (never forced) push lands only while main is still $base.
    if git push origin "$tip:refs/heads/main"; then break; fi
    pushes=$((pushes + 1))
    [ "$pushes" -lt 6 ] || refuse "main moved during each of 6 pushes; run land.sh ${train[*]} again"
    git fetch --quiet origin main '+refs/notchcast/synced/*:refs/notchcast/synced/*'
    moved_to=$(git rev-parse origin/main)
    [ "$moved_to" != "$base" ] || refuse "push to main failed and main did not move from ${base:0:8}"
    previous=$base
    base=$moved_to
    # Trees, not the commit range: a Sync rewrite of main changes real files and still reruns.
    moved=$(git diff --name-only "$previous" "$base") || refuse 'cannot read how main moved'
    # A harness (ext-test.swift) loads the runtime JS, so a move changing it still reruns them.
    if [ -z "$(grep -vxF -f <(python3 -c 'from notchcast.ci import GENERATED, RUNTIME_JS; print("\n".join(set(GENERATED) - {RUNTIME_JS}))') <<< "$moved" || true)" ]; then
        echo "main moved ${previous:0:8} -> ${base:0:8} only in generated files; merging again without rerunning harnesses"
    else
        echo "main moved ${previous:0:8} -> ${base:0:8}; merging again and rerunning harnesses"
        rerun=1
    fi
done
unclosed=
parent=$base
for pr in "${train[@]}"; do
    load "$pr"
    commit=$(< "$scratch/commit-$pr")
    if gh pr close "$pr" -R "$FORK_REPO" --comment "Landed on main as $commit by notchcast/land.sh: squash of $head onto $parent."; then
        delete_head "$(jq -r .headRefName <<< "$metadata")" "$head" "$(jq -r .isCrossRepository <<< "$metadata")"
    else
        unclosed="$unclosed #$pr"
    fi
    parent=$commit
done
prepare_drift_tools "$base"
drift_report "$base" "$tip"
[ -z "$unclosed" ] || refuse "landed on main as $tip, but closing$unclosed failed: close by hand, do not rerun land.sh"
finished=1
