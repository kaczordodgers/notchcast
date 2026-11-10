#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ci-finishes.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/notchcast" "$WORK/Scripts" "$WORK/bin" "$WORK/home"
cp "$ROOT/notchcast/ci-tests.sh" "$ROOT/notchcast/test-harnesses.sh" "$ROOT/notchcast/harness_inputs.py" \
    "$ROOT/notchcast/command-harness-sources.sh" "$WORK/notchcast/"
printf 'CI_SKIP_TESTS=skip\nUPSTREAM_REPO=upstream/repo\nFORK_REPO=fork/repo\n' > "$WORK/notchcast/config.env"
# Upstream's runner as test-harnesses.sh meets it: a finished queue, `ran`, `only`; then what is left to dispatch.
cat > "$WORK/Scripts/run-tests.sh" <<'RUNNER'
#!/bin/bash
set -uo pipefail
QUEUE="$TMPDIR/queue" emit_db=0 only=${1:-} ran=0
: > "$QUEUE"
for name in alpha alphabet beta gamma skip; do
    [ -z "$only" ] || [ "$name" = "$only" ] || continue
    echo "1 $name -Onone Source.swift" >> "$QUEUE"
    ran=$((ran + 1))
done
source notchcast/test-harnesses.sh
echo "$ran:$(cut -d' ' -f2 "$QUEUE" | tr '\n' ' ')"
RUNNER
chmod +x "$WORK/Scripts/run-tests.sh"
printf '#!/bin/bash\nexit 0\n' > "$WORK/bin/git"
chmod +x "$WORK/bin/git"
if [ "${1:-}" = --mutate-only ]; then
    sed -i '' 's/NOTCHCAST_ONLY_TESTS/DISABLED_ONLY_TESTS/g' "$WORK/notchcast/test-harnesses.sh"
fi
cd "$WORK"
export PATH="$WORK/bin:$PATH" RUNNER_TEMP="$WORK" TMPDIR="$WORK"
unset NOTCHCAST_ONLY_TESTS NOTCHCAST_SHARD NOTCHCAST_SWIFTC_CACHE
bash notchcast/ci-tests.sh > baseline 2>&1
printf 'skipped on the runner: skip\n4:alpha alphabet beta gamma \n' > expected
diff -u expected baseline
NOTCHCAST_ONLY_TESTS='alpha skip ' bash notchcast/ci-tests.sh > selected 2>&1
printf 'skipped on the runner: skip\n1:alpha \n' > expected
diff -u expected selected
echo 'PASS: unset selection keeps the suite less the runner skips; a selection narrows the queue by exact name'
for shard in 0 1 2; do
    NOTCHCAST_SHARD="$shard 3" bash notchcast/ci-tests.sh 2>/dev/null | cut -d: -f2 | tr ' ' '\n'
done | grep . | sort > shards
printf 'alpha\nalphabet\nbeta\ngamma\n' > expected
diff -u expected shards
[ "$(NOTCHCAST_SHARD='0 3' bash notchcast/ci-tests.sh 2>/dev/null)" != "$(NOTCHCAST_SHARD='1 3' bash notchcast/ci-tests.sh 2>/dev/null)" ]
for shard in 0 1 2; do
    [ "$(NOTCHCAST_SHARD="$shard 3" NOTCHCAST_ONLY_TESTS=alpha ./Scripts/run-tests.sh beta)" = '1:beta ' ]
done
echo 'PASS: shards split the queue with every harness in exactly one; a named harness runs in any shard'
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
