#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
sed -n '/^    for attempt in /,/^    done/p' "$root/notchcast/land.sh" > "$scratch/retry"
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
if [ "$1" = push ]; then
    echo push >> "$PUSHES"
    if [ "$(wc -l < "$PUSHES")" -eq 1 ]; then
        "$REAL_GIT" update-ref refs/remotes/origin/main "$MOVED"
        exit 1
    fi
    exit 0
fi
if [ "$1" = fetch ]; then exit 0; fi
exec "$REAL_GIT" "$@"
STUB
chmod +x "$scratch/bin/git"
export REAL_GIT=$(command -v git) PUSHES="$scratch/pushes"
cd "$scratch"
git init -q
git config user.name Damian
git config user.email 336236323+kaczordodgers@users.noreply.github.com
echo base > base.txt
git add .
git commit -qm 'Fixture base'
base=$(git rev-parse HEAD)
echo moved > main.txt
git add main.txt
git commit -qm 'Fixture main'
export MOVED=$(git rev-parse HEAD)
git switch -q --detach "$base"
echo consumer > consumer.txt
git add consumer.txt
git commit -qm 'Fixture consumer'
head=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$base"
export PATH="$scratch/bin:$PATH"
commit=$head
pr=1
pr_files=consumer.txt
generated=(generated.txt)
printf 'Fixture squash\n' > "$scratch/message"
refuse() { echo "REFUSED: $*"; exit 1; }
merge_onto() { echo rebuilt >> "$scratch/rebuilt"; }
harnesses() { refuse 'selected harness detects removed API in disjoint file'; }
status=0
(source "$scratch/retry") > "$scratch/output" 2>&1 || status=$?
if [ "$status" -ne 1 ] || ! grep -q 'selected harness detects removed API' "$scratch/output"; then
    echo 'FAIL: disjoint retry skipped harnesses'
    exit 1
fi
[ "$(wc -l < "$PUSHES")" -eq 1 ]
[ "$(wc -l < "$scratch/rebuilt")" -eq 1 ]
echo 'PASS: disjoint retry reruns harnesses and refuses before second push'
