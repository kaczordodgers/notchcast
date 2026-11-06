#!/bin/bash
set -euo pipefail
script=$(cd "$(dirname "$0")" && pwd)/prune-branches.py
scratch=$(mktemp -d "${NOTCHCAST_SCRATCH:-${TMPDIR:-/tmp}}/prune-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
git init -q --bare "$scratch/remote.git"
git clone -q "$scratch/remote.git" "$scratch/repo"
cd "$scratch/repo"
git config user.name Fixture
git config user.email fixture@example.com
export GIT_AUTHOR_DATE='2020-01-01T00:00:00Z' GIT_COMMITTER_DATE='2020-01-01T00:00:00Z'
git switch -q -c main
echo base > file
git add file
git commit -qm base
base=$(git rev-parse HEAD)
git update-ref refs/remotes/upstream/main "$base"
for name in ancestor open nc-design-race-one nc-design-v4-one dirty locked outside clean fail-tree fail-branch; do git branch "$name"; done
git switch -q -c patch
echo patch > patch
git add patch
git commit -qm patch
git switch -q main
git commit -q --allow-empty -m diverge
git cherry-pick patch >/dev/null
git switch -q -c squash "$base"
echo squash > squash
git add squash
git commit -qm squash
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
echo second >> squash
git add squash
git commit -qm second
tip=$(git rev-parse HEAD)
for name in other-author no-subject upstream-subject wrong-prefix; do git branch "$name"; done
export GIT_AUTHOR_DATE='2020-01-01T00:00:00Z' GIT_COMMITTER_DATE='2020-01-01T00:00:00Z'
git switch -q main
echo unrelated > unrelated
git add unrelated
git commit -qm unrelated
git merge --squash squash >/dev/null
git commit -qm 'Notchcast: landed (#1)'
landed=$(git rev-parse HEAD)
git commit --amend -qm 'Notchcast: rebased landing (#1)'
! git merge-base --is-ancestor "$landed" HEAD
git commit -q --allow-empty -m 'Notchcast: other author (#2)'
git commit -q --allow-empty -m 'Upstream: wrong prefix (#5)'
git commit-tree "$base^{tree}" -p "$base" -m 'Notchcast: upstream only (#4)' > "$scratch/upstream-tip"
git update-ref refs/remotes/upstream/main "$(cat "$scratch/upstream-tip")"
git merge -q -s ours --no-edit upstream/main
git switch -q -c unlanded "$base"
echo unlanded > unlanded
git add unlanded
git commit -qm unlanded
git switch -q -c merge-only "$base"
git merge -q --no-ff --no-commit patch
echo resolved > resolved
git add resolved
git commit -qm 'hand-resolved merge'
[ -z "$(git cherry main merge-only | grep '^+' || true)" ]
git switch -q main
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
export GIT_AUTHOR_DATE=$(date -u -v-36H '+%Y-%m-%dT%H:%M:%SZ')
export GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE
git commit -q --allow-empty -m age-36-hours
git branch age-36-hours
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
git switch -q -c recent
git commit -q --allow-empty -m recent
git branch recent-ancestor
git switch -q main
git merge -q --ff-only recent-ancestor
git switch -q main
git push -q origin --all
mkdir "$scratch/allowed" "$scratch/bin"
for name in dirty locked clean fail-tree; do git worktree add -q "$scratch/allowed/$name" "$name"; done
git worktree add -q "$scratch/outside" outside
echo dirty > "$scratch/allowed/dirty/untracked"
git worktree lock "$scratch/allowed/locked"
printf '#!/bin/bash\n[[ " $* " == *" -R kaczordodgers/notchcast "* ]] || exit 1\ncase "$*" in\n*open*) echo '\''[{"headRefName":"open"}]'\'' ;;\n*) cat "%s/comments.json" ;;\nesac\n' "$scratch" > "$scratch/bin/gh"
printf '[{"number":1,"headRefName":"squash","comments":[{"author":{"login":"kaczordodgers"},"body":"Landed on main as %s by land: squash of %s onto base."}]}' "$landed" "$tip" > "$scratch/comments.json"
number=2
for name in other-author no-subject upstream-subject wrong-prefix; do
    author=kaczordodgers
    if [ "$name" = other-author ]; then author=someone-else; fi
    printf ',{"number":%s,"headRefName":"%s","comments":[{"author":{"login":"%s"},"body":"Landed on main as %s by land: squash of %s onto base."}]}' "$number" "$name" "$author" "$landed" "$tip" >> "$scratch/comments.json"
    number=$((number + 1))
done
printf ']\n' >> "$scratch/comments.json"
real_git=$(command -v git)
printf '#!/bin/bash\ncase "$*" in\n"worktree remove "*/fail-tree|"branch -D -- fail-branch") echo "fixture removal failure" >&2; exit 1 ;;\nesac\nexec "%s" "$@"\n' "$real_git" > "$scratch/bin/git"
chmod +x "$scratch/bin/gh"
chmod +x "$scratch/bin/git"
export PATH="$scratch/bin:$PATH"
upstream=$(git rev-parse upstream/main)
git update-ref -d refs/remotes/upstream/main
if python3 "$script" --remote --dry-run --log "$scratch/dry.tsv" > "$scratch/missing-output" 2>&1; then
    echo 'FAIL: missing upstream/main was accepted' >&2
    exit 1
fi
grep -q 'upstream/main is missing' "$scratch/missing-output"
git update-ref refs/remotes/upstream/main "$upstream"
if python3 "$script" --local --dry-run --log "$scratch/dry.tsv" --worktree-root "$HOME" > "$scratch/home-output" 2>&1; then
    echo 'FAIL: a worktree root containing the home folder was accepted' >&2
    exit 1
fi
grep -q 'contains the home folder' "$scratch/home-output"
python3 "$script" --remote --local --dry-run --log "$scratch/dry.tsv" --worktree-root "$scratch/allowed" > "$scratch/dry-output"
for name in other-author no-subject upstream-subject wrong-prefix; do
    ! grep -q "Candidate .*: $name$" "$scratch/dry-output"
done
! git merge-base --is-ancestor "$landed" origin/main
grep -q 'Candidate local: squash' "$scratch/dry-output"
grep -q 'Candidate local: age-36-hours' "$scratch/dry-output"
! grep -q 'Candidate .*: recent' "$scratch/dry-output"
git merge-base --is-ancestor recent-ancestor origin/main
[ "$(git show -s --format=%ct refs/heads/squash)" -gt "$(date -v-24H +%s)" ]
[ "$(git show -s --format=%ct recent-ancestor)" -gt "$(date -v-24H +%s)" ]
[ ! -e "$scratch/dry.tsv" ]
python3 "$script" --remote --local --log "$scratch/log.tsv" --worktree-root "$scratch/allowed" > "$scratch/output"
cat "$scratch/output"
for name in main open nc-design-race-one nc-design-v4-one recent recent-ancestor unlanded merge-only dirty locked outside fail-tree fail-branch; do git show-ref --verify --quiet "refs/heads/$name"; done
for name in ancestor patch squash clean age-36-hours; do
    ! git show-ref --verify --quiet "refs/heads/$name"
    [ -z "$(git ls-remote origin "refs/heads/$name")" ]
done
[ ! -d "$scratch/allowed/clean" ]
[ -d "$scratch/allowed/fail-tree" ]
grep -q 'Kept remove failed: 2' "$scratch/output"
grep -q 'Warning: worktree remove failed for fail-tree' "$scratch/output"
grep -q 'Warning: branch remove failed for fail-branch' "$scratch/output"
for reason in main 'open PR' design recent 'not landed' 'dirty worktree' 'locked worktree' 'worktree outside roots'; do grep -q "Kept $reason:" "$scratch/output"; done
grep -q $'clean\t.*\tworktree\t' "$scratch/log.tsv"
echo 'PASS: prune landed proofs, keep rules, dry-run and ledger'
