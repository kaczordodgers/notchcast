#!/bin/bash
set -euo pipefail
tools=$(cd "$(dirname "$0")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/gh" <<'STUB'
#!/bin/bash
if [ "$1 $2" = 'pr view' ]; then echo '{"headRefOid":"fixture","baseRefOid":"base"}'; fi
if [ "$1 $2" = 'variable get' ]; then
    [ -s "$HOLD_FILE" ] && cat "$HOLD_FILE" || { echo 'variable LANDING_HOLD was not found' >&2; exit 1; }
fi
STUB
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
if [ "$1" = clone ]; then
    tree=${@: -1}
    echo "$tree" >> "$EVENTS"
    mkdir -p "$tree"
fi
STUB
cat > "$scratch/bin/python3" <<'STUB'
#!/bin/bash
if [ "$1" = -c ]; then echo fixture; exit 0; fi
if [[ "$1" == */check-drift.py ]]; then [ -z "${DRIFT_FAIL:-}" ] || echo 'gate 1: FAIL'; exit "${DRIFT_FAIL:-0}"; fi
echo "builder $RUN"
echo "$RUN: $*" >> "$QUEUE_CALLS"
sleep 1
STUB
chmod +x "$scratch/bin/"*
export PATH="$scratch/bin:$PATH" HOME="$scratch/home" EVENTS="$scratch/events"
export HOLD_FILE="$scratch/hold" QUEUE_CALLS="$scratch/queue" NOTCHCAST_HOLD_POLL_SECONDS=1
export NOTCHCAST_BUILD_QUEUE="python3 $scratch/build-queue.py" NOTCHCAST_LOCAL_CI_DIR="$scratch/local-ci"
script=${LOCAL_CI_SCRIPT:-$tools/local-ci.sh}
RUN=one bash "$script" 1 > "$scratch/one" 2>&1 &
one=$!
RUN=two bash "$script" 1 > "$scratch/two" 2>&1 &
two=$!
status=0
wait "$one" || status=1
wait "$two" || status=1
[ "$status" -eq 0 ] || { cat "$scratch/one" "$scratch/two"; exit 1; }
[ "$(sort -u "$EVENTS" | wc -l | tr -d ' ')" -eq 2 ] || { echo 'FAIL: concurrent runs share a worktree'; exit 1; }
grep -q 'builder' "$NOTCHCAST_LOCAL_CI_DIR/logs/fixture.log"
while read -r tree; do [ ! -e "$(dirname "$tree")" ]; done < "$EVENTS"
echo 'PASS: concurrent same-head runs use distinct worktrees and retain the stable log'
! grep -q "^$HOME/\|^$NOTCHCAST_LOCAL_CI_DIR/" "$EVENTS" || { cat "$EVENTS"; echo 'FAIL: tree under the home'; exit 1; }
echo 'PASS: the build tree lives outside the home'
grep -q '^one: .*build-queue.py hold -- bash ' "$QUEUE_CALLS" || { cat "$QUEUE_CALLS"; echo 'FAIL: no hold, normal lane'; exit 1; }
# During a landing hold the owner's build takes the priority lane and every other PR's local CI waits.
later=$(($(date +%s) + 600))
echo "1 $later" > "$HOLD_FILE"
RUN=owner bash "$script" 1 > "$scratch/owner" 2>&1 || { cat "$scratch/owner"; exit 1; }
grep -q '^owner: .*build-queue.py hold --landing -- bash ' "$QUEUE_CALLS" || { cat "$QUEUE_CALLS"; echo 'FAIL: the hold owner did not go first'; exit 1; }
echo 'PASS: the hold owner builds in the landing lane'
echo "330 $later" > "$HOLD_FILE"
RUN=other bash "$script" 1 > "$scratch/other" 2>&1 &
other=$!
sleep 3
! grep -q '^other:' "$QUEUE_CALLS" || { echo 'FAIL: another PR built during the hold'; exit 1; }
grep -q 'local CI waits: landing is held for 330' "$scratch/other" || { cat "$scratch/other"; echo 'FAIL: no wait message'; exit 1; }
: > "$HOLD_FILE"
wait "$other" || { cat "$scratch/other"; exit 1; }
grep -q '^other: .*build-queue.py hold -- bash ' "$QUEUE_CALLS" || { cat "$QUEUE_CALLS"; echo 'FAIL: the waiting build did not run after release'; exit 1; }
echo 'PASS: another PR waits for the hold, then builds in the normal lane'
# land.sh's own auto hold is no reason to stall other PRs' builds or to reorder the queue.
echo "330 $later auto" > "$HOLD_FILE"
RUN=autoother bash "$script" 1 > "$scratch/autoother" 2>&1 &
autoother=$!
sleep 3
grep -q '^autoother: .*build-queue.py hold -- bash ' "$QUEUE_CALLS" || { kill "$autoother" 2>/dev/null; cat "$scratch/autoother"; echo 'FAIL: waited on an auto hold'; exit 1; }
wait "$autoother"
! grep -q 'local CI waits' "$scratch/autoother" || { echo 'FAIL: wait message under an auto hold'; exit 1; }
echo "1 $later auto" > "$HOLD_FILE"
RUN=autoowner bash "$script" 1 > "$scratch/autoowner" 2>&1 || { cat "$scratch/autoowner"; exit 1; }
grep -q '^autoowner: .*build-queue.py hold -- bash ' "$QUEUE_CALLS" || { cat "$QUEUE_CALLS"; echo 'FAIL: auto hold owner changed lane'; exit 1; }
: > "$HOLD_FILE"
echo 'PASS: local CI does not wait on, or reorder for, an auto hold'
if DRIFT_FAIL=1 RUN=drift bash "$script" 1 > "$scratch/drift" 2>&1; then echo 'FAIL: drift passed'; exit 1; fi
grep -q '^REFUSED: drift baseline grew$' "$scratch/drift" || { cat "$scratch/drift"; echo 'FAIL: no drift refusal'; exit 1; }
grep -q '^failure: .*, drift; log: ' "$scratch/drift" || { cat "$scratch/drift"; echo 'FAIL: status step is not drift'; exit 1; }
! grep -q '^drift:' "$QUEUE_CALLS" || { echo 'FAIL: built after a drift refusal'; exit 1; }
echo 'PASS: a drift refusal fails local CI before the build'
