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
if [ "$1" = diff ] && [ -n "${DIFF_FAILS:-}" ]; then echo 'fatal: bad object' >&2; exit 128; fi
exec "$REAL_GIT" "$@"
STUB
chmod +x "$scratch/bin/git"
export REAL_GIT=$(command -v git) PUSHES="$scratch/pushes"
cd "$scratch"
git init -q
git config user.name Damian
git config user.email 336236323+kaczordodgers@users.noreply.github.com
echo base > base.txt
mkdir notchcast
printf 'RUNTIME_JS = "runtime.js"\nGENERATED = ["generated.txt", RUNTIME_JS]\n' > notchcast/ci.py
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
MAINTAINER_NAME=$(git config user.name) MAINTAINER_EMAIL=$(git config user.email)
refuse() { echo "REFUSED: $*"; exit 1; }
merge_onto() { echo rebuilt >> "$scratch/rebuilt"; }
harnesses() { refuse 'selected harness detects removed API in disjoint file'; }
source "$root/notchcast/hold.sh"
gh() { [ -n "${HOLD:-}" ] && echo "$HOLD" || { echo 'variable LANDING_HOLD was not found' >&2; return 1; }; }
status=0
(source "$scratch/retry") > "$scratch/output" 2>&1 || status=$?
if [ "$status" -ne 1 ] || ! grep -q 'selected harness detects removed API' "$scratch/output"; then
    echo 'FAIL: disjoint retry skipped harnesses'
    exit 1
fi
[ "$(wc -l < "$PUSHES")" -eq 1 ]
[ "$(wc -l < "$scratch/rebuilt")" -eq 1 ]
echo 'PASS: disjoint retry reruns harnesses and refuses before second push'
# A hold set for another PR while this one ran its harnesses stops it before the push.
: > "$PUSHES"
git update-ref refs/remotes/origin/main "$base"
HOLD="330 $(($(date +%s) + 600))"
status=0
(source "$scratch/retry") > "$scratch/output" 2>&1 || status=$?
if [ "$status" -ne 1 ] || ! grep -q 'landing is held for 330' "$scratch/output"; then
    cat "$scratch/output"
    echo 'FAIL: a hold set during the check did not stop the push'
    exit 1
fi
[ ! -s "$PUSHES" ]
echo 'PASS: a hold set during the check refuses before the push'
# Main moving only in a generated file (the Generated workflow's push) merges again but skips the harnesses.
HOLD=
git switch -q --detach "$base"
echo regenerated > generated.txt
git add generated.txt
git commit -qm 'Fixture generated'
export MOVED=$(git rev-parse HEAD)
git switch -q --detach "$head"
: > "$PUSHES"
rm -f "$scratch/rebuilt"
git update-ref refs/remotes/origin/main "$base"
harnesses() { echo harnesses >> "$scratch/harnessed"; }
status=0
(source "$scratch/retry") > "$scratch/output" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ -e "$scratch/harnessed" ] || ! grep -q 'only in generated files' "$scratch/output"; then
    cat "$scratch/output"
    echo 'FAIL: a generated-only move reran the harnesses'
    exit 1
fi
[ "$(wc -l < "$PUSHES")" -eq 2 ]
[ "$(wc -l < "$scratch/rebuilt")" -eq 1 ]
echo 'PASS: a generated-only move merges again, skips the harnesses and pushes'
# An unreadable move must not pass as generated-only.
: > "$PUSHES"
rm -f "$scratch/rebuilt" "$scratch/harnessed"
git update-ref refs/remotes/origin/main "$base"
status=0
(DIFF_FAILS=1 source "$scratch/retry") > "$scratch/output" 2>&1 || status=$?
if [ "$status" -ne 1 ] || [ -e "$scratch/harnessed" ] || ! grep -q 'cannot read how main moved' "$scratch/output"; then
    cat "$scratch/output"
    echo 'FAIL: an unreadable move skipped the harnesses'
    exit 1
fi
[ "$(wc -l < "$PUSHES")" -eq 1 ]
echo 'PASS: an unreadable move refuses before the second push'
# The runtime JS is generated but a harness loads it, so a move touching it reruns the harnesses.
git switch -q --detach "$base"
echo rebuilt > runtime.js
git add runtime.js
git commit -qm 'Fixture runtime'
export MOVED=$(git rev-parse HEAD)
git switch -q --detach "$head"
: > "$PUSHES"
rm -f "$scratch/rebuilt"
git update-ref refs/remotes/origin/main "$base"
status=0
(source "$scratch/retry") > "$scratch/output" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ ! -e "$scratch/harnessed" ] || ! grep -q 'rerunning harnesses' "$scratch/output"; then
    cat "$scratch/output"
    echo 'FAIL: a runtime JS move skipped the harnesses'
    exit 1
fi
[ "$(wc -l < "$PUSHES")" -eq 2 ]
echo 'PASS: a runtime JS move merges again and reruns the harnesses'
