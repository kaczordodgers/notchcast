#!/bin/bash
set -uo pipefail
APP=${1:?usage: verify-signature.sh <app> <upstream script>}
UPSTREAM=${2:?usage: verify-signature.sh <app> <upstream script>}
OUTPUT=$(bash "$UPSTREAM" "$APP" 2>&1)
STATUS=$?
printf '%s\n' "$OUTPUT"
FAILURES=0
while IFS= read -r LINE; do
    case "$LINE" in
        *✗*)
            FAILURES=$((FAILURES + 1))
            case "$LINE" in
                *': not signed with a timestamped Developer ID') ;;
                *) exit 1 ;;
            esac
            ;;
    esac
done <<< "$OUTPUT"
if [ "$STATUS" -ne 0 ] && [ "$FAILURES" -eq 0 ]; then
    exit "$STATUS"
fi
