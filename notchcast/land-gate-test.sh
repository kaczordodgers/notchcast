#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/repo/notchcast" "$scratch/bin"
cp "$root/notchcast/land.sh" "$root/notchcast/local-build-status.sh" "$scratch/repo/notchcast/"
cat > "$scratch/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
    *--json*state*) printf '{"state":"OPEN","isDraft":false,"headRefOid":"%s","headRefName":"fixture","baseRefName":"%s"}\n' "$HEAD_SHA" "$BASE_NAME" ;;
    *check-runs*)
        echo "$*" >> "$CALLS"
        case "$*" in
            *check_name=build*) echo "$BUILD" ;;
            *check_name=Design*) echo "$DESIGN" ;;
            *check_name=Leaks*) echo "$LEAKS" ;;
            *) exit 3 ;;
        esac ;;
    *statuses*) echo false ;;
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
export CALLS="$scratch/calls" BASE_NAME=main BUILD=success DESIGN=success LEAKS=success
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
    for verdict in failure pending none cancelled; do
        export "$name=$verdict"
        run
        grep -qi "REFUSED:.*$name" "$scratch/output" || { echo "FAIL: $name $verdict accepted"; exit 1; }
        grep -q "commits/$HEAD_SHA/check-runs" "$CALLS"
        echo "PASS: $name $verdict refused on captured head"
    done
    export "$name=success"
done
run
[ "$status" -eq 77 ]
grep -q REACHED_MERGE "$scratch/output"
echo 'PASS: green checks reach merged-tree validation'
