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
printf '%s\n' '#!/bin/bash' 'echo "✓ App signature verified"' 'exit 0' > "$TEMP/upstream.sh"
bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"
echo 'PASS: successful upstream verification is accepted'
