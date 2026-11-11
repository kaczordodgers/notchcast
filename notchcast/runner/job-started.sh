#!/bin/bash
# Runner hook: publish this Mac's idle count now, so a run planned in the next minute is not sent to a busy runner.
# shellcheck disable=SC2086
nohup /bin/bash "$(dirname "$0")/gate.sh" $NOTCHCAST_RUNNER_GATE >> "$HOME/Library/Logs/notchcast/runner-gate.log" 2>&1 &
exit 0
