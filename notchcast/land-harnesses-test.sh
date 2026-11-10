#!/bin/bash
# land.sh's merged-tree harness step against a stand-in selector, runner and PR-build lookup.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/tools" "$scratch/tree/Scripts" "$scratch/tmp"
sed -n '/^harnesses() {$/,/^}$/p' "$root/notchcast/land.sh" > "$scratch/harnesses"
grep -q run-tests.sh "$scratch/harnesses"
printf '#!/bin/bash\nprintf "%%s\\n" $SELECTED\n' > "$scratch/tools/changed-harnesses.sh"
# Stands in for ci.py tested-run: a run URL when a green PR build tested this tree, else exit 1.
printf '#!/bin/bash\n[ -n "${TESTED:-}" ] && echo "$TESTED"\n' > "$scratch/tools/python3"
# One line per call, then the real runner's verdict lines for the names it was narrowed to.
cat > "$scratch/tree/Scripts/run-tests.sh" <<'RUNNER'
#!/bin/bash
echo "$NOTCHCAST_ONLY_TESTS" >> "$CALLS"
set -- $NOTCHCAST_ONLY_TESTS
[ -z "${DROP:-}" ] || shift
if [ -n "${BROKEN:-}" ]; then
    printf '\n\033[31mFAILED\033[0m  1 of %d harness(es) failed in 3s: %s\n' "$#" "$BROKEN" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in 3s.\n' "$#"
RUNNER
chmod +x "$scratch/tools/changed-harnesses.sh" "$scratch/tools/python3" "$scratch/tree/Scripts/run-tests.sh"
export PATH="$scratch/tools:$PATH" CALLS="$scratch/calls" SELECTED='a-test b-test vm-test'
selector="$scratch/tools/changed-harnesses.sh"
CI_SKIP_TESTS='vm-test other-test'
refuse() { echo "REFUSED: $*"; exit 1; }
cd "$scratch/tree"
source "$scratch/harnesses"
check() {
    local expected=$1 status=0
    rm -f "$CALLS"
    (harnesses base) > "$scratch/output" 2>&1 || status=$?
    [ "$status" -eq "$expected" ] || { echo "FAIL: exit $status, expected $expected"; cat "$scratch/output"; exit 1; }
}
check 0
[ "$(cat "$CALLS")" = 'a-test b-test vm-test ' ]
echo 'PASS: every selected harness runs in one runner call'
BROKEN=b-test check 1
grep -qx 'REFUSED: b-test failed' "$scratch/output"
echo 'PASS: a failing harness refuses the landing by name'
DROP=1 check 1
grep -qx 'REFUSED: the runner did not run all 3 selected harnesses' "$scratch/output"
echo 'PASS: a selected harness the runner does not run refuses the landing'
TESTED=https://example.invalid/run check 0
[ "$(cat "$CALLS")" = 'vm-test ' ]
grep -q 'already tested by https://example.invalid/run' "$scratch/output"
echo 'PASS: a green PR build of the merged tree leaves only the harnesses the hosted runner skips'
SELECTED='a-test b-test' TESTED=https://example.invalid/run check 0
[ ! -e "$CALLS" ]
echo 'PASS: with none of those selected the runner is not called'
