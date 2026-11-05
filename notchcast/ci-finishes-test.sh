#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ci-finishes.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/notchcast" "$WORK/Scripts" "$WORK/bin" "$WORK/home"
cp "$ROOT/notchcast/ci-tests.sh" "$WORK/notchcast/"
printf 'CI_SKIP_TESTS=skip\nUPSTREAM_REPO=upstream/repo\nFORK_REPO=fork/repo\n' > "$WORK/notchcast/config.env"
printf '#!/bin/bash\nset -eu\nrun_test() {\n    local name=$1\n    echo "compiled $name"\n}\nfor name in alpha alphabet skip; do run_test "$name"; done\n' > "$WORK/Scripts/run-tests.sh"
chmod +x "$WORK/Scripts/run-tests.sh"
printf '#!/bin/bash\nexit 0\n' > "$WORK/bin/git"
chmod +x "$WORK/bin/git"
if [ "${1:-}" = --mutate-only ]; then
    sed -i '' 's/NOTCHCAST_ONLY_TESTS/DISABLED_ONLY_TESTS/g' "$WORK/notchcast/ci-tests.sh"
fi
cp "$WORK/Scripts/run-tests.sh" "$WORK/original"
cd "$WORK"
export PATH="$WORK/bin:$PATH" RUNNER_TEMP="$WORK" TMPDIR="$WORK"
unset NOTCHCAST_ONLY_TESTS
bash notchcast/ci-tests.sh > baseline 2>&1
printf 'compiled alpha\ncompiled alphabet\nskipped on the runner: skip\n' > expected
diff -u expected baseline
cp original Scripts/run-tests.sh
NOTCHCAST_ONLY_TESTS=alpha bash notchcast/ci-tests.sh > selected 2>&1
printf 'compiled alpha\n' > expected
diff -u expected selected
echo 'PASS: unset selection preserves baseline; selection filters before compilation silently'
sed '/^export PATH=/d' "$ROOT/notchcast/kick.sh" > notchcast/kick.sh
if [ "${1:-}" = --mutate-skip ]; then
    sed -i '' 's/if \[ "$pending" != 0 \]/if [ "$pending" = impossible ]/' notchcast/kick.sh
fi
printf '#!/bin/bash\ncase "$*" in\n  *"commits/main"*) echo upstream;;\n  "release list"*) echo release;;\n  "run list"*) echo "${PENDING:-1}";;\n  "workflow run"*) echo dispatch >> "$CALLS";;\n  *compare*) echo 0;;\n  *) echo "unexpected gh: $*" >&2; exit 1;;\nesac\n' > bin/gh
chmod +x bin/gh
export HOME="$WORK/home" CALLS="$WORK/calls"
mkdir -p "$HOME/Library/Application Support/notchcast"
STATE="$HOME/Library/Application Support/notchcast/kick.state"
printf 'old old 1\n' > "$STATE"
cp "$STATE" state-before
for pending in 1 2 3; do
    PENDING=$pending bash notchcast/kick.sh > kick-log
    grep -q 'skip sync: a run is queued/pending/waiting' kick-log
    diff -u state-before "$STATE"
    test ! -e "$CALLS"
done
bash notchcast/kick.sh --dry-run > kick-log
grep -q 'skip sync:' kick-log
diff -u state-before "$STATE"
test ! -e "$CALLS"
PENDING=0 bash notchcast/kick.sh --dry-run > kick-log
grep -q 'would start sync' kick-log
test ! -e "$CALLS"
PENDING=0 bash notchcast/kick.sh > kick-log
grep -q 'started sync' kick-log
test "$(cat "$CALLS")" = dispatch
grep -q '^upstream release ' "$STATE"
echo 'PASS: pending Sync skips dispatch and preserves state; dry-run reports skip; idle dispatches'
