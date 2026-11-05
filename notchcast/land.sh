#!/bin/bash
set -euo pipefail
# A stale checkout lands by stale rules (one skipped the Sync wait), so a landing always runs main's tooling.
if [ "$#" -eq 1 ] && [ -z "${NOTCHCAST_LAND_TOOLS:-}" ]; then
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
    [ -n "${NOTCHCAST_LAND_ORIGIN:-}" ] || return 0
    cd "$NOTCHCAST_LAND_ORIGIN"
    git worktree remove --force "$NOTCHCAST_LAND_TOOLS/tree" >/dev/null 2>&1 || true
    rm -rf "$NOTCHCAST_LAND_TOOLS"
}
trap remove_tools EXIT
source "$(dirname "$0")/local-build-status.sh"
selector="$(cd "$(dirname "$0")" && pwd)/changed-harnesses.sh"
cd "$(git rev-parse --show-toplevel)"
refuse() { echo "REFUSED: $*" >&2; exit 1; }
source "$(dirname "$0")/sync-wait.sh"
source "$(dirname "$0")/hold.sh"
check=0
if [ "${1:-}" = --check ] && [ "$#" -eq 3 ]; then
    check=1
    base=$(git rev-parse --verify "$2^{commit}")
    head=$(git rev-parse --verify "$3^{commit}")
elif [ "$#" -eq 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    pr=$1
    metadata=$(gh pr view "$pr" -R kaczordodgers/notchcast --json state,isDraft,headRefOid,headRefName,baseRefName)
    [ "$(jq -r .baseRefName <<< "$metadata")" = main ] || refuse 'PR base must be main'
    check_hold "$pr"
    head=$(python3 -c 'import json,sys; p=json.load(sys.stdin); assert p["state"] == "OPEN" and not p["isDraft"], "PR must be open and ready"; print(p["headRefOid"])' <<< "$metadata") || refuse 'PR must be open and ready'
    git fetch origin main "refs/pull/$pr/head" '+refs/notchcast/synced/*:refs/notchcast/synced/*'
    git cat-file -e "$head^{commit}" || refuse 'PR head unavailable'
    for name in design leaks; do
        verdict=$(gh api "repos/kaczordodgers/notchcast/commits/$head/check-runs?check_name=$name&filter=all" \
            --jq '[.check_runs[] | select(.app.slug == "github-actions")] | max_by(.started_at) | if . == null then "none" elif .status != "completed" then "pending" else .conclusion end')
        [ "$verdict" = none ] || [ "$verdict" = success ] || refuse "$name is $verdict on ${head:0:8}; wait for success"
    done
    required=$(python3 notchcast/app-proof.py plan origin/main "$head")
    if [ -n "$required" ]; then
        verdict=$(gh api "repos/kaczordodgers/notchcast/commits/$head/check-runs?check_name=proof&filter=all" \
            --jq '[.check_runs[] | select(.app.slug == "github-actions")] | max_by(.started_at) | if . == null then "none" elif .status != "completed" then "pending" else .conclusion end')
        branch=$(jq -r .headRefName <<< "$metadata")
        [ "$verdict" = success ] || refuse "real-app proof ($required) is $verdict on ${head:0:8}; it runs on the PR, or: gh workflow run Proof --ref $branch -R kaczordodgers/notchcast"
    fi
    # Check runs on the commit, not the PR's statusCheckRollup: the rollup omits dispatched runs, and a PR
    # GitHub calls conflicting gets no pull_request run at all. The newest run wins over a cancelled one.
    build() {
        gh api "repos/kaczordodgers/notchcast/commits/$1/check-runs?check_name=build&filter=all" \
            --jq '[.check_runs[] | select(.app.slug == "github-actions")] | max_by(.started_at) | if . == null then "none" elif .status != "completed" then "pending" else .conclusion end'
    }
    green() { [ "$(build "$1")" = success ] || local_build_green "$1"; }
    verdict=$(build "$head")
    if local_build_green "$head"; then verdict=success; fi
    [ "$verdict" = success ] || [ "$verdict" = none ] || [ "$verdict" = cancelled ] \
        || refuse "build is $verdict on ${head:0:8}: wait for it or fix it (cancel a pending one to use a green head that differs only in generated files)"
    if [ "$verdict" != success ]; then
        # A head that differs from a green head of this branch only in generated files needs no new build:
        # CI regenerates them before every build, so the green build already proved this code.
        branch=$(jq -r .headRefName <<< "$metadata")
        generated=$(python3 -c 'from notchcast.ci import GENERATED; print("\n".join(GENERATED))')
        proven=
        for sha in $(git rev-list --max-count=30 "$head") $(gh run list -R kaczordodgers/notchcast -w PR -b "$branch" -L 30 --json headSha,conclusion \
                --jq '.[] | select(.conclusion == "success") | .headSha' | awk '!seen[$0]++'); do
            git fetch -q origin "$sha" 2>/dev/null && green "$sha" || continue
            [ -n "$(git diff --name-only "$sha" "$head" | grep -vxF "$generated")" ] || { proven=$sha; break; }
        done
        [ -n "$proven" ] || refuse "build is not green on ${head:0:8}; if it has none, run: gh workflow run PR --ref $branch -R kaczordodgers/notchcast"
        echo "build: ${head:0:8} differs from green ${proven:0:8} only in generated files"
    fi
    base=$(git rev-parse origin/main)
else
    refuse 'usage: land.sh <pr> | --check <base-ref> <head-ref>'
fi
scratch=$(mktemp -d)
cleanup() {
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    rm -rf "$scratch"
    remove_tools
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$scratch/tmp"
top=$(pwd)
# Sync's rebase rewrites main, so a PR cut before it shares only upstream with the new main, and a plain merge sees
# every one of our commits twice. sync.yml records each replaced main tip under refs/notchcast/synced/; the PR's
# fork point is its merge base with the newest such tip whose shared history main no longer has. A PR that merged
# the new main since ("Update branch") has a plain merge base outside that tip and keeps the plain merge.
# Merges $head onto $1 in a fresh scratch tree and runs the cheap checks; any real conflict is refused.
merge_onto() {
    local onto=$1 file revived unmerged
    cd "$top"
    fork=$(bash "$(dirname "$selector")/fork-point.sh" "$onto" "$head")
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    git worktree add --quiet --detach "$scratch/tree" "$onto"
    cd "$scratch/tree"
    if [ "$fork" = "$(git merge-base "$onto" "$head")" ]; then
        git -c core.hooksPath=/dev/null merge --no-commit --no-ff "$head" >/dev/null 2>&1 || true
    else
        echo "merging from ${fork:0:8}, the PR's fork point on main before a Sync rewrite"
        git merge-recursive "$fork" -- HEAD "$head" >/dev/null 2>&1 || true
        git rev-parse "$head" > "$(git rev-parse --git-path MERGE_HEAD)"
    fi
    # Generated files (ci.py GENERATED) keep main's version, conflicting or not: CI regenerates them before every
    # build, so the PR's copies never land and the green head still proves the code. Any other conflict is refused.
    generated=($(python3 -c 'from notchcast.ci import GENERATED; print(" ".join(GENERATED))'))
    git checkout "$onto" -- "${generated[@]}"
    # The string catalog conflicts on neighbouring keys; xcstrings-union.py merges it by key or exits non-zero.
    if git diff --name-only --diff-filter=U | grep -qxF Tinycast/Resources/Localizable.xcstrings; then
        python3 notchcast/xcstrings-union.py --git --main-ref "$onto" || refuse 'string catalog conflict xcstrings-union.py cannot merge'
    fi
    if git diff --name-only --diff-filter=U | grep -qxF Tinycast/Resources/Notchcast.xcstrings; then
        python3 notchcast/xcstrings-union.py --git --main-ref "$onto" --catalog Tinycast/Resources/Notchcast.xcstrings || refuse 'fork string catalog conflict'
    fi
    unmerged=$(git diff --name-only --diff-filter=U)
    [ -z "$unmerged" ] || refuse "merge conflict: $(echo $unmerged)"
    git -c core.hooksPath=/dev/null -c user.name=Damian -c user.email=336236323+kaczordodgers@users.noreply.github.com \
        commit --quiet --allow-empty --no-edit -m "Merge $head"
    # A union merge keeps a line the PR deleted when main appended next to it; refuse instead of reviving it.
    for file in $(awk '$2 == "merge=union" {print $1}' .gitattributes); do
        revived=$(comm -12 <(comm -23 <(git show "$fork:$file" 2>/dev/null | sort -u) <(git show "$head:$file" 2>/dev/null | sort -u)) \
            <(sort -u "$file" 2>/dev/null))
        [ -z "$revived" ] || refuse "union merge revives lines the PR removed from $file: $revived"
    done
    [ "$(git rev-parse 'HEAD^{tree}')" != "$(git rev-parse "$onto^{tree}")" ] || refuse 'nothing to land: main already has this change'
    python3 notchcast/check-feature-shape.py || refuse 'feature shape'
    # A union merge can leave a body Swift accepts with only a warning: it returns the last expression.
    typecheck=$(swiftc -swift-version 6 -warnings-as-errors -typecheck Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift 2>&1) \
        || refuse "NotchcastFeature*.swift does not typecheck without warnings on the merged tree: $(grep -m3 -E 'error|warning' <<< "$typecheck")"
    notchcast/check-bundle-readme.sh || refuse 'two README.md files under Tinycast/ break the Xcode build'
}
harnesses() {
    local name
    TMPDIR="$scratch/tmp" "$selector" "$1" HEAD > "$scratch/selected"
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        TMPDIR="$scratch/tmp" ./Scripts/run-tests.sh "$name" || refuse "$name failed"
    done < "$scratch/selected"
}
merge_onto "$base"
harnesses "$base"
echo 'PASS: merged-tree harnesses'
# Squash here, not on GitHub: GitHub ignores .gitattributes merge=union and calls union-only overlaps conflicts.
# Not covered without an Xcode build of this tree: code no selected harness compiles (UI, AppCore wiring,
# resources); the PR build covered the head alone, and the main harness job, Sync and Snapshot follow on main.
if [ "$check" -eq 0 ]; then
    title=$(gh pr view "$pr" -R kaczordodgers/notchcast --json title --jq .title)
    [[ "$title" == Notchcast:* ]] || title="Notchcast: $title"
    printf '%s (#%s)\n' "$title" "$pr" > "$scratch/message"
    notchcast/check-identity.sh message "$scratch/message" || refuse 'commit message names something private'
    commit=$(GIT_AUTHOR_NAME=Damian GIT_AUTHOR_EMAIL=336236323+kaczordodgers@users.noreply.github.com \
        GIT_COMMITTER_NAME=Damian GIT_COMMITTER_EMAIL=336236323+kaczordodgers@users.noreply.github.com \
        git commit-tree "HEAD^{tree}" -p "$base" -F "$scratch/message")
    wait_for_sync
    [ "$(gh pr view "$pr" -R kaczordodgers/notchcast --json headRefOid --jq .headRefOid)" = "$head" ] \
        || refuse "PR #$pr moved past ${head:0:8} during the check; run land.sh $pr again"
    # The new commit's only parent is $base, so this plain (never forced) push lands only while main is still $base.
    for attempt in 1 2 3 4 5 6; do
        check_hold "$pr"  # a hold set while the harnesses ran wins
        git push origin "$commit:refs/heads/main" && break
        [ "$attempt" -lt 6 ] || refuse "main moved during each of 6 pushes; run land.sh $pr again"
        git fetch --quiet origin main '+refs/notchcast/synced/*:refs/notchcast/synced/*'
        moved_to=$(git rev-parse origin/main)
        [ "$moved_to" != "$base" ] || refuse "push to main failed and main did not move from ${base:0:8}"
        echo "main moved ${base:0:8} -> ${moved_to:0:8}; merging again and rerunning harnesses"
        base=$moved_to
        merge_onto "$base"
        harnesses "$base"
        commit=$(GIT_AUTHOR_NAME=Damian GIT_AUTHOR_EMAIL=336236323+kaczordodgers@users.noreply.github.com \
            GIT_COMMITTER_NAME=Damian GIT_COMMITTER_EMAIL=336236323+kaczordodgers@users.noreply.github.com \
            git commit-tree "HEAD^{tree}" -p "$base" -F "$scratch/message")
    done
    gh pr close "$pr" -R kaczordodgers/notchcast --comment "Landed on main as $commit by notchcast/land.sh: squash of $head onto $base." \
        || refuse "landed on main as $commit, but closing PR #$pr failed: close it by hand, do not rerun land.sh"
fi
