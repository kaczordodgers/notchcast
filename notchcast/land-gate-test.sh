#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/repo/notchcast" "$scratch/bin"
cp "${LAND_SCRIPT:-$root/notchcast/land.sh}" "$scratch/repo/notchcast/land.sh"
cp "$root/notchcast/local-build-status.sh" "$root/notchcast/sync-wait.sh" "$root/notchcast/hold.sh" "$scratch/repo/notchcast/"
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
            *) echo none ;;
        esac ;;
    *statuses*)
        if [ "$LOCAL_BUILD" = success ]; then
            printf '{"id":1,"url":"https://api.github.com/repos/kaczordodgers/notchcast/statuses/%s","state":"success"}\n' "$HEAD_SHA"
        fi ;;
    *variable\ get\ LANDING_HOLD*)
        [ -z "${HOLD_ERROR:-}" ] || { echo 'HTTP 502: Bad Gateway' >&2; exit 1; }
        [ -n "${HOLD:-}" ] || { echo 'variable LANDING_HOLD was not found' >&2; exit 1; }
        echo "$HOLD" ;;
    *) exit 3 ;;
esac
STUB
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
case "$1" in
    fetch|cat-file) exit 0 ;;
    worktree) exit 0 ;;
    push) echo 'unexpected push' >&2; exit 99 ;;
    rev-parse)
        if [ "$2" = origin/main ]; then echo 'REACHED_MERGE' >&2; exit 77; fi ;;
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
run() {
    : > "$CALLS"
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
later=$(($(date +%s) + 600))
export HOLD="330 $later"
run
grep -q 'REFUSED: landing is held for 330 until' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: a hold for another PR was ignored'; exit 1; }
! grep -q check-runs "$CALLS"
echo 'PASS: a hold for another PR refuses before any check'
export HOLD="1 $later"
run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: the hold owner PR was refused'; exit 1; }
echo 'PASS: the PR that owns the hold lands'
export HOLD="strings $later"
NOTCHCAST_LAND_AS=strings run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: the named hold owner was refused'; exit 1; }
echo 'PASS: NOTCHCAST_LAND_AS owner lands'
export HOLD="330 $(($(date +%s) - 1))"
run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: an expired hold still refused'; exit 1; }
echo 'PASS: an expired hold is ignored'
export HOLD= HOLD_ERROR=1
run
grep -q 'REFUSED: cannot read the landing hold' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: an unreadable hold was ignored'; exit 1; }
echo 'PASS: an unreadable hold refuses'
for bad in '330' "330 $later extra" '330 later' '330 1e9' "330 0$later"; do
    export HOLD="$bad" HOLD_ERROR=
    run
    grep -q 'REFUSED: malformed landing hold' "$scratch/output" || { cat "$scratch/output"; echo "FAIL: malformed hold '$bad' was ignored"; exit 1; }
done
echo 'PASS: a malformed hold refuses'
