#!/bin/bash
set -uo pipefail
APP=${1:?usage: verify-signature.sh <app> <upstream script>}
UPSTREAM=${2:?usage: verify-signature.sh <app> <upstream script>}
OUTPUT=$(bash "$UPSTREAM" "$APP" 2>&1)
STATUS=$?
printf '%s\n' "$OUTPUT"
[ "$STATUS" -eq 0 ] && exit 0
[ "$STATUS" -eq 1 ] || exit "$STATUS"
MATCHED=0
while IFS= read -r LINE; do
    case "$LINE" in
        '') ;;
        *': not signed with a timestamped Developer ID') MATCHED=1 ;;
        *) exit "$STATUS" ;;
    esac
done <<< "$OUTPUT"
[ "$MATCHED" -eq 1 ] || exit "$STATUS"
exit 0
