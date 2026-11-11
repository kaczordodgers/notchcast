#!/bin/bash
# Runner hook, installed outside any checkout so no job can edit it. A job starts on this Mac only when the repository
#   owner started the run from this repository's own ref; anything else, or anything unknown, is refused.
#   A refusal kills the process that started this hook, the runner's worker: after a hook that only fails, the runner
#   still runs the job's `if: always()` steps and its actions' pre scripts (actions/runner#2811).
#   An admitted job publishes this Mac's idle count now, so a run planned in the next minute is not sent to a busy runner.
set -u
REPO=${NOTCHCAST_RUNNER_GATE#* }
refuse() { echo "notchcast runner: refused, $1" >&2; kill -9 "$PPID"; exit 1; }
[ -n "$REPO" ] && [ "${GITHUB_REPOSITORY:-}" = "$REPO" ] || refuse "repository '${GITHUB_REPOSITORY:-}'"
[ "${GITHUB_ACTOR:-}" = "${REPO%%/*}" ] || refuse "actor '${GITHUB_ACTOR:-}'"
[ -f "${GITHUB_EVENT_PATH:-}" ] || refuse "no event file"
case "${GITHUB_EVENT_NAME:-}" in
    push | workflow_dispatch) ;;
    pull_request)
        head=$(plutil -extract pull_request.head.repo.full_name raw -o - "$GITHUB_EVENT_PATH" 2>/dev/null) || head=""
        [ "$head" = "$REPO" ] || refuse "pull request from '$head'"
        ;;
    *) refuse "event '${GITHUB_EVENT_NAME:-}'" ;;
esac
# shellcheck disable=SC2086
nohup /bin/bash "$(dirname "$0")/gate.sh" $NOTCHCAST_RUNNER_GATE >> "$HOME/Library/Logs/notchcast/runner-gate.log" 2>&1 &
exit 0
