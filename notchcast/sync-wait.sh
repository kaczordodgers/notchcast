# Sourced by land.sh and generated.yml: anything that pushes main waits while a Sync run holds its main lease.
# Plan records main as the replay's lease, so a push from plan's start to replay's end makes Sync lose it.
# The caller defines refuse.
source "$(dirname "${BASH_SOURCE[0]}")/config.env"
wait_for_sync() {
    local run runs jobs replay deadline status
    local poll=${NOTCHCAST_TEST_SYNC_POLL_SECONDS:-30}
    local limit=${NOTCHCAST_TEST_SYNC_LIMIT_SECONDS:-2400}
    deadline=$((SECONDS + limit))
    while :; do
        replay=
        runs=$(for status in queued in_progress; do
            gh run list -R "$FORK_REPO" --workflow sync.yml --status "$status" --limit 1000 \
                --json databaseId --jq '.[].databaseId' || exit 1
        done) || refuse 'could not list Sync runs'
        for run in $runs; do
            jobs=$(gh run view "$run" -R "$FORK_REPO" --json jobs \
                --jq '(any(.jobs[]; .name == "plan" and .status == "in_progress"))
                    or ([.jobs[].name] == ["plan"] and any(.jobs[]; .name == "plan" and .conclusion == "success"))
                    or any(.jobs[]; .name == "replay" and (.status == "queued" or .status == "in_progress"))') \
                || refuse "could not read Sync run $run"
            if [ "$jobs" = true ]; then
                replay=$run
                break
            fi
        done
        [ -n "$replay" ] || return 0
        [ "$SECONDS" -lt "$deadline" ] || refuse "Sync run $replay (plan or replay) still running after 40 min; try again"
        echo "Waiting for Sync run $replay (plan or replay): pushing main now would invalidate its main lease"
        sleep "$((poll < deadline - SECONDS ? poll : deadline - SECONDS))"
    done
}
