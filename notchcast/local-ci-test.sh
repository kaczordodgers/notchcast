#!/bin/bash
set -euo pipefail
tools=$(cd "$(dirname "$0")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/gh" <<'STUB'
#!/bin/bash
if [ "$1 $2" = 'pr view' ]; then echo '{"headRefOid":"fixture","baseRefOid":"base"}'; fi
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
echo "builder $RUN"
sleep 1
STUB
chmod +x "$scratch/bin/"*
export PATH="$scratch/bin:$PATH" HOME="$scratch/home" EVENTS="$scratch/events"
unset T3CODE_THREAD_ID
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
grep -q 'builder' "$HOME/agents/nc-local-ci/logs/fixture.log"
[ -z "$(find "$HOME/agents/nc-local-ci" -name 'build.*' -print)" ]
echo 'PASS: concurrent same-head runs use distinct worktrees and retain the stable log'
