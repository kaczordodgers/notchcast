#!/bin/bash
# land.sh <pr> from a checkout whose notchcast/ differs from origin/main runs main's copy, then cleans up.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
printf '#!/bin/sh\necho "gh stub: $*" >&2\nexit 1\n' > "$scratch/bin/gh"
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"
git init --quiet --bare "$scratch/origin.git"
git init --quiet -b main "$scratch/work"
cd "$scratch/work"
git config user.name Damian
git config user.email 336236323+kaczordodgers@users.noreply.github.com
cp -R "$root/notchcast" notchcast
git add notchcast
git -c core.hooksPath=/dev/null commit --quiet -m old
old=$(git rev-parse HEAD)
sed -i '' '2a\
echo "MAIN COPY"
' notchcast/land.sh
git -c core.hooksPath=/dev/null commit --quiet -am new
git remote add origin "$scratch/origin.git"
git push --quiet origin main
git checkout --quiet --detach "$old"

output=$(bash notchcast/land.sh 42 2>&1) && { echo "FAIL: stub gh should refuse"; exit 1; }
[[ "$output" == *"running main's copy"* && "$output" == *"MAIN COPY"* ]] \
    || { echo "FAIL: stale checkout ran its own land.sh"; echo "$output"; exit 1; }
[ "$(git worktree list | wc -l)" -eq 1 ] || { echo "FAIL: tools worktree left behind"; git worktree list; exit 1; }
echo "PASS: stale checkout runs main's land.sh and removes its tools tree"

git checkout --quiet --detach origin/main
output=$(bash notchcast/land.sh 42 2>&1) && { echo "FAIL: stub gh should refuse"; exit 1; }
[[ "$output" != *"running main's copy"* && "$output" == *"MAIN COPY"* ]] \
    || { echo "FAIL: current checkout re-executed"; echo "$output"; exit 1; }
echo "PASS: current checkout runs in place"

echo '# local edit' >> notchcast/land.sh
output=$(bash notchcast/land.sh 42 2>&1) && { echo "FAIL: stub gh should refuse"; exit 1; }
[[ "$output" == *"running main's copy"* ]] || { echo "FAIL: edited land.sh ran in place"; echo "$output"; exit 1; }
echo "PASS: uncommitted tooling edits run main's copy"
