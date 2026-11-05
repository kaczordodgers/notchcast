#!/bin/bash
set -euo pipefail
TOOLS=$(cd "$(dirname "$0")" && pwd)
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
printf '%s\n' '#!/bin/bash' 'echo "✗ App: not signed with a timestamped Developer ID" >&2' 'exit 1' > "$TEMP/upstream.sh"
bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"
echo 'PASS: Developer ID failure is allowed'
printf '%s\n' '#!/bin/bash' 'echo "✗ App: not signed with a timestamped Developer ID"' 'echo "✗ App: seal does not verify"' 'exit 1' > "$TEMP/upstream.sh"
if bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"; then
    echo 'FAIL: other signature failure was accepted' >&2
    exit 1
fi
echo 'PASS: other signature failures are enforced'
printf '%s\n' '#!/bin/bash' 'exit 2' > "$TEMP/upstream.sh"
if bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"; then
    echo 'FAIL: silent upstream failure was accepted' >&2
    exit 1
fi
echo 'PASS: silent upstream failure is enforced'
printf '%s\n' '#!/bin/bash' 'exit 1' > "$TEMP/upstream.sh"
if bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"; then
    echo 'FAIL: silent exit 1 was accepted' >&2
    exit 1
fi
echo 'PASS: silent exit 1 is enforced'
printf '%s\n' '#!/bin/bash' 'echo "✓ App signature verified"' 'exit 0' > "$TEMP/upstream.sh"
bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"
echo 'PASS: successful upstream verification is accepted'
FAILURES=0
printf '%s\n' '#!/bin/bash' 'echo "✗ App: not signed with a timestamped Developer ID"' 'exit 3' > "$TEMP/upstream.sh"
STATUS=0
bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh" || STATUS=$?
if [ "$STATUS" -eq 3 ]; then
    echo 'PASS: Developer ID line plus exit 3 preserves failure status'
else
    echo "FAIL: Developer ID line plus exit 3 returned $STATUS" >&2
    FAILURES=$((FAILURES + 1))
fi
printf '%s\n' '#!/bin/bash' 'set -u' 'unset MISSING' 'echo "✗ App: not signed with a timestamped Developer ID"' 'echo "$MISSING"' > "$TEMP/upstream.sh"
STATUS=0
bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh" || STATUS=$?
if [ "$STATUS" -eq 1 ]; then
    echo 'PASS: Developer ID line plus unbound-variable abort preserves failure status'
else
    echo "FAIL: Developer ID line plus unbound-variable abort returned $STATUS" >&2
    FAILURES=$((FAILURES + 1))
fi
exit "$FAILURES"
