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
    'variable set LANDING_HOLD -R kaczordodgers/notchcast --body '*) echo "${*: -1}" > "$STORE"; [ -z "${RACE_VALUE:-}" ] || echo "$RACE_VALUE" > "$STORE" ;;
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
later=$(($(date +%s) + 600))
rm -f "$STORE"
echo "330 $later" > "$STORE"
status=0
bash "$hold" set 7 5 > "$scratch/output" 2>&1 || status=$?
[ "$status" -eq 1 ] && grep -q "^REFUSED: landing is held for 330 until " "$scratch/output" && [ "$(cat "$STORE")" = "330 $later" ] \
    || { cat "$scratch/output"; echo 'FAIL: set over a foreign live hold'; exit 1; }
echo 'PASS: set refuses over another owner'"'"'s live hold and leaves it'
bash "$hold" set --handover 7 5 > /dev/null
read -r owner until < "$STORE"
[ "$owner" = 7 ] || { echo 'FAIL: --handover'; exit 1; }
bash "$hold" set 7 20 > /dev/null
read -r owner until < "$STORE"
[ "$owner" = 7 ] && [ "$until" -ge $(($(date +%s) + 1190)) ] || { echo 'FAIL: the owner could not extend its hold'; exit 1; }
echo "330 $(($(date +%s) - 1))" > "$STORE"
bash "$hold" set 7 5 > /dev/null
echo '330 later' > "$STORE"
bash "$hold" set 7 5 > /dev/null
read -r owner until < "$STORE"
[ "$owner" = 7 ] || { echo 'FAIL: set over an expired or malformed hold'; exit 1; }
echo 'PASS: --handover, the same owner, an expired or a malformed hold can be set over'
status=0
GH_FAIL=1 bash "$hold" set 8 5 > /dev/null 2>&1 || status=$?
[ "$status" -eq 1 ] && [ "$(cat "$STORE")" = "$owner $until" ] || { echo 'FAIL: set over an unreadable hold'; exit 1; }
status=0
bash "$hold" set --handover 7 > /dev/null 2>&1 || status=$?
[ "$status" -eq 2 ] || { echo 'FAIL: --handover without minutes'; exit 1; }
echo 'PASS: set refuses when the hold cannot be read; --handover needs its arguments'
echo "330 $later auto" > "$STORE"
bash "$hold" show | grep -q '^landing held for 330 until ' || { echo 'FAIL: show of an auto hold'; exit 1; }
status=0
bash "$hold" set 7 5 > /dev/null 2>&1 || status=$?
[ "$status" -eq 1 ] || { echo 'FAIL: set over a foreign auto hold'; exit 1; }
echo 'PASS: an auto hold is a live hold'
claim() { (source "$hold"; refuse() { echo "REFUSED: $*"; exit 1; }; hold_claim "$@"; echo "claimed=$hold_claimed"; hold_release_claimed; echo "left=$([ -f "$STORE" ] && cat "$STORE")") > "$scratch/output" 2>&1; }
rm -f "$STORE"
: > "$CALLS"
before=$(date +%s)
claim 7
read -r owner until auto < <(sed -n 's/^claimed=//p' "$scratch/output")
[ "$owner" = 7 ] && [ "$auto" = auto ] && [ "$until" -ge $((before + 9000)) ] || { cat "$scratch/output"; echo 'FAIL: hold_claim'; exit 1; }
grep -q '^left=$' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: hold_release_claimed'; exit 1; }
echo 'PASS: hold_claim takes an auto hold, hold_release_claimed gives it back'
echo "7 $later" > "$STORE"
: > "$CALLS"
claim 7
! grep -q 'variable' <(grep -v 'variable get' "$CALLS") && grep -q "^left=7 $later$" "$scratch/output" && grep -q '^claimed=$' "$scratch/output" \
    || { cat "$scratch/output"; echo 'FAIL: the owner took or released its own hold'; exit 1; }
echo "330 $later" > "$STORE"
status=0
claim 7 || status=$?
grep -q '^REFUSED: landing is held for 330 until ' "$scratch/output" && [ "$(cat "$STORE")" = "330 $later" ] || { cat "$scratch/output"; echo 'FAIL: claim over a foreign hold'; exit 1; }
echo "330 $(($(date +%s) - 1))" > "$STORE"
claim 7
grep -q '^claimed=7 ' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: claim over an expired hold'; exit 1; }
echo 'PASS: hold_claim leaves its own hold, refuses a foreign one, takes an expired one'
rm -f "$STORE"
RACE_VALUE="330 $later" claim 7 || true
grep -q '^REFUSED: another lander took the landing hold first' "$scratch/output" && [ "$(cat "$STORE")" = "330 $later" ] \
    || { cat "$scratch/output"; echo 'FAIL: lost write race'; exit 1; }
echo 'PASS: hold_claim refuses when it lost a write race'
