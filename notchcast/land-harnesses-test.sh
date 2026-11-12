#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/Scripts" "$scratch/notchcast" "$scratch/bin"
cp "$root/notchcast/test-harnesses.sh" "$scratch/notchcast/"
cat > "$scratch/bin/python3" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$scratch/bin/python3"
cat > "$scratch/Scripts/run-tests.sh" <<'STUB'
#!/bin/bash
set -euo pipefail
QUEUE="$TMPDIR/queue"
only= emit_db=0 ran=2
printf '1 selected -Onone\n1 unrelated -Onone\n' > "$QUEUE"
source notchcast/test-harnesses.sh
[[ "$(cat "$QUEUE")" == '1 selected -Onone' ]]
mkdir -p "$TMPDIR/tinycast-harness"
touch "$TMPDIR/tinycast-harness/selected.log"
STUB
chmod +x "$scratch/Scripts/run-tests.sh"
export PATH="$scratch/bin:$PATH"
unset CI_SKIP_TESTS NOTCHCAST_SHARD
eval "$(sed -n '/^run_harnesses() {$/,/^}$/p' "$root/notchcast/land.sh")"
refuse() { echo "REFUSED: $*" >&2; exit 1; }
cd "$scratch"
before=$(shasum Scripts/run-tests.sh)
run_harnesses selected
[ -z "$failed" ]
[ "$before" = "$(shasum Scripts/run-tests.sh)" ]
echo 'PASS: landing selects its harness through the fork queue without editing the upstream runner'
