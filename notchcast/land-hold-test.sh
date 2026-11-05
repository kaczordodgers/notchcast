#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
case "$*" in
    'variable get LANDING_HOLD -R kaczordodgers/notchcast')
        [ -z "${GH_FAIL:-}" ] || { echo 'HTTP 502: Bad Gateway' >&2; exit 1; }
        [ -f "$STORE" ] && cat "$STORE" || { echo 'variable LANDING_HOLD was not found' >&2; exit 1; } ;;
    'variable set LANDING_HOLD -R kaczordodgers/notchcast --body '*) echo "${*: -1}" > "$STORE" ;;
    'variable delete LANDING_HOLD -R kaczordodgers/notchcast') rm "$STORE" ;;
    *) exit 3 ;;
esac
STUB
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH" CALLS="$scratch/calls" STORE="$scratch/store"
hold="$root/notchcast/hold.sh"
[ "$(bash "$hold" show)" = 'no landing hold' ] || { echo 'FAIL: show without a hold'; exit 1; }
before=$(date +%s)
bash "$hold" set 330 30 > "$scratch/output"
read -r owner until < "$STORE"
[ "$owner" = 330 ] && [ "$until" -ge $((before + 1800)) ] && [ "$until" -le $(($(date +%s) + 1800)) ] \
    || { echo "FAIL: set stored '$owner $until'"; exit 1; }
grep -q '^landing held for 330 until ' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: set output'; exit 1; }
bash "$hold" show | grep -q '^landing held for 330 until ' || { echo 'FAIL: show with a hold'; exit 1; }
echo 'PASS: set stores the owner and expiry; show reads it'
bash "$hold" release
[ ! -e "$STORE" ] && [ "$(bash "$hold" show)" = 'no landing hold' ] || { echo 'FAIL: release'; exit 1; }
echo 'PASS: release removes the hold'
echo "330 $(($(date +%s) - 1))" > "$STORE"
[ "$(bash "$hold" show)" = 'no landing hold (330 expired)' ] || { echo 'FAIL: show of an expired hold'; exit 1; }
echo 'PASS: an expired hold shows as none'
for args in 'set 330' 'set 330 soon' 'set "two words" 5' 'unhold'; do
    status=0
    eval "bash \"$hold\" $args" > /dev/null 2>&1 || status=$?
    [ "$status" -eq 2 ] || { echo "FAIL: '$args' exited $status"; exit 1; }
done
echo 'PASS: bad arguments exit 2'
bash "$hold" set 330 010 > /dev/null
read -r owner until < "$STORE"
[ "$until" -ge $(($(date +%s) + 590)) ] || { echo 'FAIL: minutes read as octal'; exit 1; }
bash "$hold" set 330 08 > /dev/null
echo 'PASS: minutes with a leading zero are decimal'
echo '330 later' > "$STORE"
status=0
bash "$hold" show > "$scratch/output" || status=$?
[ "$status" -eq 1 ] && grep -q 'malformed landing hold' "$scratch/output" || { echo 'FAIL: show of a malformed hold'; exit 1; }
rm "$STORE"
status=0
GH_FAIL=1 bash "$hold" show > /dev/null 2>&1 || status=$?
[ "$status" -ne 0 ] || { echo 'FAIL: show hid a read error'; exit 1; }
echo 'PASS: show reports a malformed or unreadable hold'
