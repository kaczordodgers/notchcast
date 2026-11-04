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
    # Check runs on the head commit, not the PR's statusCheckRollup: the rollup omits dispatched runs, and a PR
    # GitHub calls conflicting gets no pull_request run at all. The newest run wins over a cancelled one.
    gh api "repos/kaczordodgers/notchcast/commits/$head/check-runs?check_name=build&filter=all" \
        --jq '[.check_runs[] | select(.app.slug == "github-actions")] | max_by(.started_at) | .conclusion' | grep -qx success \
        || refuse "build is not green on ${head:0:8}; if it has none, run: gh workflow run PR --ref $(jq -r .headRefName <<< "$metadata") -R kaczordodgers/notchcast"
    git fetch origin main "refs/pull/$pr/head"
    git cat-file -e "$head^{commit}" || refuse 'PR head unavailable'
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
git worktree add --quiet --detach "$scratch/tree" "$base"
cd "$scratch/tree"
git -c core.hooksPath=/dev/null merge --no-commit --no-ff "$head" >/dev/null 2>&1 || true
# Generated files (ci.py GENERATED) keep main's version, conflicting or not: CI regenerates them before every build,
# so the PR's copies never land and the green head still proves the code. Any other conflict is refused.
generated=($(python3 -c 'from notchcast.ci import GENERATED; print(" ".join(GENERATED))'))
git checkout "$base" -- "${generated[@]}"
# The string catalog conflicts on neighbouring keys; xcstrings-union.py merges it by key or exits non-zero.
if git diff --name-only --diff-filter=U | grep -qxF Tinycast/Resources/Localizable.xcstrings; then
    python3 notchcast/xcstrings-union.py --git --main-ref "$base" || refuse 'string catalog conflict xcstrings-union.py cannot merge'
fi
unmerged=$(git diff --name-only --diff-filter=U)
[ -z "$unmerged" ] || refuse "merge conflict: $(echo $unmerged)"
git -c core.hooksPath=/dev/null -c user.name=Damian -c user.email=336236323+kaczordodgers@users.noreply.github.com \
    commit --quiet --allow-empty --no-edit -m "Merge $head"
mkdir "$scratch/tmp"
export TMPDIR="$scratch/tmp"
# A union merge keeps a line the PR deleted when main appended next to it; refuse instead of reviving it.
fork=$(git merge-base "$base" "$head")
for file in $(awk '$2 == "merge=union" {print $1}' .gitattributes); do
    revived=$(comm -12 <(comm -23 <(git show "$fork:$file" 2>/dev/null | sort -u) <(git show "$head:$file" 2>/dev/null | sort -u)) \
        <(sort -u "$file" 2>/dev/null))
    [ -z "$revived" ] || refuse "union merge revives lines the PR removed from $file: $revived"
done
[ "$(git rev-parse 'HEAD^{tree}')" != "$(git rev-parse "$base^{tree}")" ] || refuse 'nothing to land: main already has this change'
python3 notchcast/check-feature-shape.py || refuse 'feature shape'
"$selector" "$base" HEAD > "$scratch/selected"
while IFS= read -r name; do
    [ -n "$name" ] || continue
    ./Scripts/run-tests.sh "$name" || refuse "$name failed"
done < "$scratch/selected"
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
    git push origin "$commit:refs/heads/main" || refuse "main moved past ${base:0:8}; run land.sh $pr again"
    gh pr close "$pr" -R kaczordodgers/notchcast --comment "Landed on main as $commit by notchcast/land.sh: squash of $head onto $base." \
        || refuse "landed on main as $commit, but closing PR #$pr failed: close it by hand, do not rerun land.sh"
fi
