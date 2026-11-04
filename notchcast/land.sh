#!/bin/bash
set -euo pipefail
selector="$(cd "$(dirname "$0")" && pwd)/changed-harnesses.sh"
cd "$(git rev-parse --show-toplevel)"
refuse() { echo "REFUSED: $*" >&2; exit 1; }
check=0
if [ "${1:-}" = --check ] && [ "$#" -eq 3 ]; then
    check=1
    base=$(git rev-parse --verify "$2^{commit}")
    head=$(git rev-parse --verify "$3^{commit}")
elif [ "$#" -eq 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    pr=$1
    metadata=$(gh pr view "$pr" -R kaczordodgers/notchcast --json state,isDraft,headRefOid,headRefName)
    head=$(python3 -c 'import json,sys; p=json.load(sys.stdin); assert p["state"] == "OPEN" and not p["isDraft"], "PR must be open and ready"; print(p["headRefOid"])' <<< "$metadata") || refuse 'PR must be open and ready'
    git fetch origin main "refs/pull/$pr/head"
    git cat-file -e "$head^{commit}" || refuse 'PR head unavailable'
    # Check runs on the commit, not the PR's statusCheckRollup: the rollup omits dispatched runs, and a PR
    # GitHub calls conflicting gets no pull_request run at all. The newest run wins over a cancelled one.
    build() {
        gh api "repos/kaczordodgers/notchcast/commits/$1/check-runs?check_name=build&filter=all" \
            --jq '[.check_runs[] | select(.app.slug == "github-actions")] | max_by(.started_at) | if . == null then "none" elif .status != "completed" then "pending" else .conclusion end'
    }
    green() { [ "$(build "$1")" = success ]; }
    verdict=$(build "$head")
    [ "$verdict" = success ] || [ "$verdict" = none ] || [ "$verdict" = cancelled ] \
        || refuse "build is $verdict on ${head:0:8}: wait for it or fix it (cancel a pending one to use a green head that differs only in generated files)"
    if [ "$verdict" != success ]; then
        # A head that differs from a green head of this branch only in generated files needs no new build:
        # CI regenerates them before every build, so the green build already proved this code.
        branch=$(jq -r .headRefName <<< "$metadata")
        generated=$(python3 -c 'from notchcast.ci import GENERATED; print("\n".join(GENERATED))')
        proven=
        for sha in $(gh run list -R kaczordodgers/notchcast -w PR -b "$branch" -L 30 --json headSha,conclusion \
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
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$scratch/tmp"
top=$(pwd)
# Merges $head onto $1 in a fresh scratch tree and runs the cheap checks; any real conflict is refused.
merge_onto() {
    local onto=$1 file revived unmerged
    cd "$top"
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    git worktree add --quiet --detach "$scratch/tree" "$onto"
    cd "$scratch/tree"
    git -c core.hooksPath=/dev/null merge --no-commit --no-ff "$head" >/dev/null 2>&1 || true
    # Generated files (ci.py GENERATED) keep main's version, conflicting or not: CI regenerates them before every
    # build, so the PR's copies never land and the green head still proves the code. Any other conflict is refused.
    generated=($(python3 -c 'from notchcast.ci import GENERATED; print(" ".join(GENERATED))'))
    git checkout "$onto" -- "${generated[@]}"
    # The string catalog conflicts on neighbouring keys; xcstrings-union.py merges it by key or exits non-zero.
    if git diff --name-only --diff-filter=U | grep -qxF Tinycast/Resources/Localizable.xcstrings; then
        python3 notchcast/xcstrings-union.py --git --main-ref "$onto" || refuse 'string catalog conflict xcstrings-union.py cannot merge'
    fi
    unmerged=$(git diff --name-only --diff-filter=U)
    [ -z "$unmerged" ] || refuse "merge conflict: $(echo $unmerged)"
    git -c core.hooksPath=/dev/null -c user.name=Damian -c user.email=336236323+kaczordodgers@users.noreply.github.com \
        commit --quiet --allow-empty --no-edit -m "Merge $head"
    # A union merge keeps a line the PR deleted when main appended next to it; refuse instead of reviving it.
    fork=$(git merge-base "$onto" "$head")
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
    [ "$(gh pr view "$pr" -R kaczordodgers/notchcast --json headRefOid --jq .headRefOid)" = "$head" ] \
        || refuse "PR #$pr moved past ${head:0:8} during the check; run land.sh $pr again"
    # The new commit's only parent is $base, so this plain (never forced) push lands only while main is still $base.
    # Each landing moves main twice (the squash, then the generated commit), so a lost race merges onto the new
    # main and retries. Harnesses rerun only when the new commits touch a file the PR touches; otherwise the clean
    # merge is the same proof GitHub's merge button gives.
    pr_files=$(git diff --name-only "$(git merge-base "$base" "$head")" "$head" | sort -u)
    for attempt in 1 2 3 4 5 6; do
        git push origin "$commit:refs/heads/main" && break
        [ "$attempt" -lt 6 ] || refuse "main moved during each of 6 pushes; run land.sh $pr again"
        git fetch --quiet origin main
        moved_to=$(git rev-parse origin/main)
        [ "$moved_to" != "$base" ] || refuse "push to main failed and main did not move from ${base:0:8}"
        overlap=$(comm -12 <(git diff --name-only "$base" "$moved_to" | grep -vxF -f <(printf '%s\n' "${generated[@]}") | sort -u) \
            <(echo "$pr_files") | sed '/^$/d')
        echo "main moved ${base:0:8} -> ${moved_to:0:8}; overlap with the PR: ${overlap:-none}"
        base=$moved_to
        merge_onto "$base"
        [ -z "$overlap" ] || harnesses "$base"
        commit=$(GIT_AUTHOR_NAME=Damian GIT_AUTHOR_EMAIL=336236323+kaczordodgers@users.noreply.github.com \
            GIT_COMMITTER_NAME=Damian GIT_COMMITTER_EMAIL=336236323+kaczordodgers@users.noreply.github.com \
            git commit-tree "HEAD^{tree}" -p "$base" -F "$scratch/message")
    done
    gh pr close "$pr" -R kaczordodgers/notchcast --comment "Landed on main as $commit by notchcast/land.sh: squash of $head onto $base." \
        || refuse "landed on main as $commit, but closing PR #$pr failed: close it by hand, do not rerun land.sh"
fi
