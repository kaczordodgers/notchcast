#!/bin/bash
# Usage: ci-priority.sh <run-id-or-pr>...   cancels every other queued PR build
#        ci-priority.sh --restore           reruns what was cancelled
set -euo pipefail

repo="${CI_PRIORITY_REPO:-kaczordodgers/notchcast}"
state="${CI_PRIORITY_STATE:-$HOME/.notchcast-ci-priority}"
touch "$state"

queued_ids() {
    local status
    for status in queued pending; do
        gh run list -R "$repo" --workflow PR --status "$status" --limit 100 \
            --json databaseId --jq '.[].databaseId'
    done
}

resolve() {
    # GitHub run ids are far longer than PR numbers.
    if [ "${#1}" -ge 8 ]; then
        echo "$1"
        return
    fi
    local sha
    sha="$(gh pr view "$1" -R "$repo" --json headRefOid --jq .headRefOid)"
    local id
    id="$(gh run list -R "$repo" --workflow PR --commit "$sha" --limit 1 \
        --json databaseId --jq '.[].databaseId')"
    [ -n "$id" ] || { echo "No PR run for #$1 at ${sha:0:8}; nothing would be exempt." >&2; exit 65; }
    echo "$id"
}

restore() {
    local id info status conclusion branch sha newest
    # Take the list aside so ids a concurrent cancel appends to $state survive.
    work="$(mktemp)"
    remaining="$(mktemp)"
    mv "$state" "$work"
    touch "$state"
    # If this pass dies, put every id back; already rerun ones are dropped next time as done.
    trap 'cat "$work" "$remaining" >>"$state"; sort -u "$state" -o "$state"' EXIT
    while read -r id; do
        [ -n "$id" ] || continue
        if ! info="$(gh run view "$id" -R "$repo" --json status,conclusion,headBranch,headSha \
            --jq '[.status, (.conclusion // "-"), .headBranch, .headSha] | @tsv')"; then
            echo "$id" >>"$remaining"
            echo "unreadable $id"
            continue
        fi
        status="$(cut -f1 <<<"$info")"
        conclusion="$(cut -f2 <<<"$info")"
        branch="$(cut -f3 <<<"$info")"
        sha="$(cut -f4 <<<"$info")"
        # A cancel still in flight cannot be rerun yet; keep it for the next pass.
        if [ "$status" != completed ]; then
            echo "$id" >>"$remaining"
            echo "waiting $id $status $branch"
            continue
        fi
        # Already rerun by an earlier, interrupted pass: it ran to a real result.
        if [ "$conclusion" != cancelled ]; then
            echo "done $id $conclusion $branch"
            continue
        fi
        newest="$(gh run list -R "$repo" --workflow PR --branch "$branch" --limit 1 \
            --json headSha --jq '.[].headSha')"
        if [ "$newest" != "$sha" ]; then
            echo "superseded $id $branch"
        elif gh run rerun "$id" -R "$repo" >/dev/null; then
            echo "rerun $id $branch"
        else
            echo "$id" >>"$remaining"
            echo "failed $id $branch"
        fi
    done <"$work"
    cat "$remaining" >>"$state"
    sort -u "$state" -o "$state"
    trap - EXIT
    rm -f "$work" "$remaining"
}

if [ "${1:-}" = "--restore" ]; then
    restore
    exit 0
fi
[ "$#" -gt 0 ] || { sed -n 2,3p "$0" >&2; exit 64; }

keep=""
for target in "$@"; do
    keep="$keep $(resolve "$target")"
done
for id in $(queued_ids); do
    case " $keep " in *" $id "*) continue ;; esac
    gh run cancel "$id" -R "$repo" >/dev/null && echo "$id" >>"$state"
done
sort -u "$state" -o "$state"
cat "$state"
