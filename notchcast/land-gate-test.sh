#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/repo/notchcast" "$scratch/bin"
cp "${LAND_SCRIPT:-$root/notchcast/land.sh}" "$scratch/repo/notchcast/land.sh"
cp "$root/notchcast/config.env" "$root/notchcast/local-build-status.sh" "$root/notchcast/sync-wait.sh" "$root/notchcast/hold.sh" "$root/notchcast/drift-gates.sh" "$scratch/repo/notchcast/"
cp "$root/notchcast/app-proof.py" "$root/notchcast/app-proofs.json" "$scratch/repo/notchcast/"
cat > "$scratch/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
    *--json*state*) printf '{"state":"OPEN","isDraft":false,"headRefOid":"%s","headRefName":"fixture","baseRefName":"%s"}\n' "$HEAD_SHA" "$BASE_NAME" ;;
    *check-runs*)
        echo "$*" >> "$CALLS"
        case "$*" in
            *check_name=build*) echo "$BUILD" ;;
            *check_name=design*) echo "$DESIGN" ;;
            *check_name=leaks*) echo "$LEAKS" ;;
            *check_name=proof*) echo "$PROOF" ;;
            *) echo none ;;
        esac ;;
    *statuses*)
        if [ "$LOCAL_BUILD" = success ]; then
            printf '{"id":1,"url":"https://api.github.com/repos/kaczordodgers/notchcast/statuses/%s","state":"success"}\n' "$HEAD_SHA"
        fi ;;
    *variable\ get\ LANDING_HOLD*)
        [ -z "${HOLD_ERROR:-}" ] || { echo 'HTTP 502: Bad Gateway' >&2; exit 1; }
        ! rm "$STORE.fail-next-get" 2>/dev/null || { echo 'HTTP 502: Bad Gateway' >&2; exit 1; }
        [ -s "$STORE" ] || { echo 'variable LANDING_HOLD was not found' >&2; exit 1; }
        cat "$STORE" ;;
    *variable\ set\ LANDING_HOLD*)
        echo "set ${*: -1}" >> "$HOLD_LOG"; echo "${*: -1}" > "$STORE"
        [ -z "${HOLD_ERROR_AFTER_SET:-}" ] || touch "$STORE.fail-next-get" ;;
    *variable\ delete\ LANDING_HOLD*) echo delete >> "$HOLD_LOG"; rm -f "$STORE" ;;
    *) exit 3 ;;
esac
STUB
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
case "$1" in
    fetch|cat-file) exit 0 ;;
    worktree) exit 0 ;;
    push) echo 'unexpected push' >&2; exit 99 ;;
    merge-base) echo fixture-base; exit 0 ;;
    diff) printf '%s\0' "${CHANGED_PATH:-unrelated.txt}"; exit 0 ;;
    rev-parse)
        if [ "$2" = origin/main ]; then
            cp "$STORE" "$HELD_AT_MERGE" 2>/dev/null
            [ -z "${REPLACE_WITH:-}" ] || echo "$REPLACE_WITH" > "$STORE"
            echo 'REACHED_MERGE' >&2; exit 77
        fi ;;
esac
exec "$REAL_GIT" "$@"
STUB
chmod +x "$scratch/bin/gh" "$scratch/bin/git"
export REAL_GIT=$(command -v git)
cd "$scratch/repo"
git init -q
export PATH="$scratch/bin:$PATH" HEAD_SHA=0123456789012345678901234567890123456789
# The script under test runs as is, not origin/main's copy.
export NOTCHCAST_LAND_TOOLS=test CALLS="$scratch/calls" BASE_NAME=main BUILD=success DESIGN=success LEAKS=success LOCAL_BUILD=none
export PROOF=none
export STORE="$scratch/store" HOLD_LOG="$scratch/hold-log" HELD_AT_MERGE="$scratch/held-at-merge"
run() {
    : > "$CALLS"
    : > "$HOLD_LOG"
    rm -f "$HELD_AT_MERGE"
    if [ -n "${HOLD:-}" ]; then echo "$HOLD" > "$STORE"; else rm -f "$STORE"; fi
    status=0
    bash notchcast/land.sh 1 > "$scratch/output" 2>&1 || status=$?
}
export BASE_NAME=topic
run
grep -q 'REFUSED:.*main' "$scratch/output" || { echo 'FAIL: non-main PR was accepted'; exit 1; }
echo 'PASS: non-main base refused'
export BASE_NAME=main
for name in BUILD DESIGN LEAKS; do
    for verdict in failure pending; do
        export "$name=$verdict"
        run
        grep -qi "REFUSED:.*$name" "$scratch/output" || { echo "FAIL: $name $verdict accepted"; exit 1; }
        grep -q "commits/$HEAD_SHA/check-runs" "$CALLS"
        echo "PASS: $name $verdict refused on captured head"
    done
    export "$name=success"
done
for name in DESIGN LEAKS; do
    export "$name=none"
    run
    [ "$status" -eq 77 ] || { cat "$scratch/output"; echo "FAIL: absent $name refused"; exit 1; }
    echo "PASS: absent $name allowed"
    export "$name=success"
done
export BUILD=pending LOCAL_BUILD=success
run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: local build lane refused'; exit 1; }
echo 'PASS: local build lane accepted'
export BUILD=success LOCAL_BUILD=none
run
[ "$status" -eq 77 ]
grep -q REACHED_MERGE "$scratch/output"
echo 'PASS: green checks reach merged-tree validation'
export CHANGED_PATH=Tinycast/Features/Music/Model/SoloistKeyValidation.swift
for verdict in none pending failure cancelled; do
    export PROOF=$verdict
    run
    grep -q "REFUSED: real-app proof (spotify-key) is $verdict" "$scratch/output"
    grep -q "commits/$HEAD_SHA/check-runs?check_name=proof" "$CALLS"
    echo "PASS: declared path with proof $verdict refused on captured head"
done
export PROOF=success
run
[ "$status" -eq 77 ]
echo 'PASS: declared path with successful proof reaches merge'
export CHANGED_PATH=unrelated.txt PROOF=none
run
[ "$status" -eq 77 ]
! grep -q check_name=proof "$CALLS"
echo 'PASS: undeclared path needs no proof'
later=$(($(date +%s) + 600))
export HOLD=
before=$(date +%s)
run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: no hold refused'; exit 1; }
read -r owner until auto < "$HELD_AT_MERGE" || { echo 'FAIL: no landing hold taken at the start'; exit 1; }
[ "$owner" = 1 ] && [ "$auto" = auto ] && [ "$until" -ge $((before + 9000)) ] && [ "$until" -le $(($(date +%s) + 9000)) ] \
    || { echo "FAIL: took '$owner $until $auto'"; exit 1; }
[ ! -e "$STORE" ] && [ "$(sed -n 2p "$HOLD_LOG")" = delete ] || { cat "$HOLD_LOG"; echo 'FAIL: the hold was not released at exit'; exit 1; }
echo 'PASS: land.sh takes an auto hold for its PR at the start and releases it at exit'
NOTCHCAST_LAND_HOLD_MINUTES=5 run
read -r owner until auto < "$HELD_AT_MERGE"
[ "$until" -le $(($(date +%s) + 300)) ] || { echo 'FAIL: NOTCHCAST_LAND_HOLD_MINUTES ignored'; exit 1; }
echo 'PASS: NOTCHCAST_LAND_HOLD_MINUTES sets the auto hold length'
export BUILD=failure
run
grep -q 'REFUSED: build is failure' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: build failure accepted'; exit 1; }
[ ! -e "$STORE" ] && [ "$(sed -n 2p "$HOLD_LOG")" = delete ] || { cat "$HOLD_LOG"; echo 'FAIL: the hold outlived a later refusal'; exit 1; }
export BUILD=success
echo 'PASS: a later refusal releases the hold'
export HOLD="330 $later"
run
grep -q 'REFUSED: landing is held for 330 until' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: a hold for another PR was ignored'; exit 1; }
! grep -q check-runs "$CALLS"
[ "$(cat "$STORE")" = "$HOLD" ] && [ ! -s "$HOLD_LOG" ] || { cat "$HOLD_LOG"; echo 'FAIL: a foreign hold was touched'; exit 1; }
echo 'PASS: a hold for another PR refuses before any check and is left alone'
export HOLD="330 $later auto"
run
grep -q 'REFUSED: landing is held for 330 until' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: a foreign auto hold was ignored'; exit 1; }
echo 'PASS: a foreign auto hold refuses'
export HOLD="1 $later"
run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: the hold owner PR was refused'; exit 1; }
[ "$(cat "$STORE")" = "$HOLD" ] && [ ! -s "$HOLD_LOG" ] || { cat "$HOLD_LOG"; echo 'FAIL: the owner took or released its own hold'; exit 1; }
echo 'PASS: the PR that owns the hold lands and takes nothing'
export HOLD="strings $later"
NOTCHCAST_LAND_AS=strings run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: the named hold owner was refused'; exit 1; }
[ ! -s "$HOLD_LOG" ] || { cat "$HOLD_LOG"; echo 'FAIL: the named owner took a hold'; exit 1; }
echo 'PASS: NOTCHCAST_LAND_AS owner lands'
export HOLD=
REPLACE_WITH="330 $later" run
[ "$status" -eq 77 ] && [ "$(cat "$STORE")" = "330 $later" ] && ! grep -q delete "$HOLD_LOG" \
    || { cat "$HOLD_LOG"; echo 'FAIL: a hold replaced during the run was released'; exit 1; }
echo 'PASS: a hold replaced during the run is not released'
export HOLD="330 $(($(date +%s) - 1))"
run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: an expired hold still refused'; exit 1; }
echo 'PASS: an expired hold is ignored'
export HOLD= HOLD_ERROR=1
run
grep -q 'REFUSED: cannot read the landing hold' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: an unreadable hold was ignored'; exit 1; }
echo 'PASS: an unreadable hold refuses'
export HOLD_ERROR=
HOLD_ERROR_AFTER_SET=1 run
grep -q 'REFUSED: cannot read the landing hold' "$scratch/output" && [ ! -e "$STORE" ] && grep -q '^delete$' "$HOLD_LOG" \
    || { cat "$scratch/output" "$HOLD_LOG"; echo 'FAIL: a claim that failed its read-back left the hold behind'; exit 1; }
echo 'PASS: a claim that failed its read-back is released at exit'
for bad in '330' "330 $later extra" '330 later' '330 1e9' "330 0$later"; do
    export HOLD="$bad" HOLD_ERROR=
    run
    grep -q 'REFUSED: malformed landing hold' "$scratch/output" || { cat "$scratch/output"; echo "FAIL: malformed hold '$bad' was ignored"; exit 1; }
done
echo 'PASS: a malformed hold refuses'
