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
    metadata=$(gh pr view "$pr" -R kaczordodgers/notchcast --json state,isDraft,headRefOid,statusCheckRollup)
    head=$(python3 -c 'import json,sys; p=json.load(sys.stdin); assert p["state"] == "OPEN" and not p["isDraft"], "PR must be open and ready"; print(p["headRefOid"])' <<< "$metadata") || refuse 'PR must be open and ready'
    # The newest run wins: a dispatched rerun sits beside the cancelled run on the same head.
    python3 -c 'import json,sys; p=json.load(sys.stdin); b=[c for c in p["statusCheckRollup"] if c.get("name") == "build"]; assert max(b, key=lambda c: c["startedAt"])["conclusion"] == "SUCCESS"' <<< "$metadata" 2>/dev/null \
        || refuse "build is not green on $head; run: gh workflow run PR --ref <branch> -R kaczordodgers/notchcast"
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
if ! git -C "$scratch/tree" -c core.hooksPath=/dev/null -c user.name=Damian \
    -c user.email=336236323+kaczordodgers@users.noreply.github.com \
    merge --no-edit --no-ff "$head"; then
    refuse 'merge conflict'
fi
mkdir "$scratch/tmp"
export TMPDIR="$scratch/tmp"
cd "$scratch/tree"
python3 notchcast/check-feature-shape.py || refuse 'feature shape'
swiftc -typecheck Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift || refuse 'feature typecheck'
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
    commit=$(GIT_AUTHOR_NAME=Damian GIT_AUTHOR_EMAIL=336236323+kaczordodgers@users.noreply.github.com \
        GIT_COMMITTER_NAME=Damian GIT_COMMITTER_EMAIL=336236323+kaczordodgers@users.noreply.github.com \
        git commit-tree "HEAD^{tree}" -p "$base" -m "$title (#$pr)")
    # The new commit's only parent is $base, so this plain (never forced) push lands only while main is still $base.
    git push origin "$commit:refs/heads/main" || refuse "main moved past ${base:0:8}; run land.sh $pr again"
    gh pr close "$pr" -R kaczordodgers/notchcast --comment "Landed on main as $commit by notchcast/land.sh: squash of $head onto $base."
fi
