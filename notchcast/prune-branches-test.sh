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
export GIT_AUTHOR_DATE='2020-01-01T00:00:00Z' GIT_COMMITTER_DATE='2020-01-01T00:00:00Z'
git switch -q main
echo unrelated > unrelated
git add unrelated
git commit -qm unrelated
git merge --squash squash >/dev/null
git commit -qm landed
landed=$(git rev-parse HEAD)
git switch -q -c unlanded "$base"
echo unlanded > unlanded
git add unlanded
git commit -qm unlanded
git switch -q main
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
printf '#!/bin/bash\n[[ " $* " == *" -R kaczordodgers/notchcast "* ]] || exit 1\ncase "$*" in\n*open*) echo '\''[{"headRefName":"open"}]'\'' ;;\n*) echo '\''[{"headRefName":"squash","comments":[{"body":"Landed on main as %s by land: squash of %s onto base."}]}]'\'' ;;\nesac\n' "$landed" "$tip" > "$scratch/bin/gh"
real_git=$(command -v git)
printf '#!/bin/bash\ncase "$*" in\n"worktree remove "*/fail-tree|"branch -D -- fail-branch") echo "fixture removal failure" >&2; exit 1 ;;\nesac\nexec "%s" "$@"\n' "$real_git" > "$scratch/bin/git"
chmod +x "$scratch/bin/gh"
chmod +x "$scratch/bin/git"
export PATH="$scratch/bin:$PATH"
python3 "$script" --remote --local --dry-run --log "$scratch/dry.tsv" --worktree-root "$scratch/allowed" > "$scratch/dry-output"
grep -q 'Candidate local: squash' "$scratch/dry-output"
! grep -q 'Candidate .*: recent' "$scratch/dry-output"
git merge-base --is-ancestor recent-ancestor origin/main
[ "$(git show -s --format=%ct refs/heads/squash)" -gt "$(date -v-24H +%s)" ]
[ "$(git show -s --format=%ct recent-ancestor)" -gt "$(date -v-24H +%s)" ]
[ ! -e "$scratch/dry.tsv" ]
python3 "$script" --remote --local --log "$scratch/log.tsv" --worktree-root "$scratch/allowed" > "$scratch/output"
cat "$scratch/output"
for name in main open nc-design-race-one nc-design-v4-one recent recent-ancestor unlanded dirty locked outside fail-tree fail-branch; do git show-ref --verify --quiet "refs/heads/$name"; done
for name in ancestor patch squash clean; do
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
