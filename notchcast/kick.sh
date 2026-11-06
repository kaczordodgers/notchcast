#!/bin/bash
# Sync trigger: GitHub's own schedule never fired for this fork, so launchd (notchcast.kick, every 10 min) starts
# sync.yml when upstream changes, and at least hourly.
# The sync decides everything else (ci.py plan); a start that finds nothing to do costs one Linux minute.
# Where ~/.config/notchcast/private.env defines notchcast_notify (notchcast/README.md, "Private hooks"), it is told
# once when this trigger fails, and once per upstream commit that is not in our main after LAG_ALERT_MIN while no
# sync issue explains it.
# Usage: kick.sh [--dry-run]
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin"

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
STATE_DIR="$HOME/Library/Application Support/notchcast"
STATE="$STATE_DIR/kick.state"
ALERTED="$STATE_DIR/kick.alerted"
HEARTBEAT_SEC=3600 LAG_ALERT_MIN=40
mkdir -p "$STATE_DIR"; touch "$STATE" "$ALERTED"
log() { printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*"; }
if [ -f "$HOME/.config/notchcast/private.env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.config/notchcast/private.env"
fi

alert_once() { # key message
    declare -F notchcast_notify >/dev/null || return 0
    grep -qxF "$1" "$ALERTED" && return 0
    if [ "$DRY" = 1 ]; then log "would alert: $2"; return 0; fi
    printf 'Notchcast: %s\n' "$2" | notchcast_notify || { log "notify failed; retried next run"; return 0; }
    echo "$1" >> "$ALERTED"
    log "notified: $2"
}

fail() {
    log "trigger failed: $1"
    alert_once "kick-failed" "the sync trigger (notchcast.kick on $(hostname -s)) fails: $1. See ~/Library/Logs/notchcast/kick.log."
    exit 1
}

upstream_main="$(gh api "repos/$UPSTREAM_REPO/commits/main" --jq .sha 2>&1)" || fail "reading upstream main: $upstream_main"
upstream_release="$(gh release list -R "$UPSTREAM_REPO" -L 1 --json tagName --jq '.[0].tagName // ""' 2>&1)" \
    || fail "reading upstream releases: $upstream_release"
want="$upstream_main $upstream_release"
read -r last_main last_release last_at < "$STATE" || true
now="$(date +%s)"

reason=""
if [ "$want" != "${last_main:-} ${last_release:-}" ]; then reason="upstream changed: $want"
elif [ $((now - ${last_at:-0})) -ge "$HEARTBEAT_SEC" ]; then reason="hourly heartbeat"
fi
if [ -n "$reason" ] || [ "$DRY" = 1 ]; then
    pending="$(gh run list -R "$FORK_REPO" --workflow sync.yml --limit 100 --json status --jq '[.[] | select(.status == "queued" or .status == "pending" or .status == "waiting")] | length' 2>&1)" || fail "reading pending sync runs: $pending"
    if [ "$pending" != 0 ]; then log "skip sync: a run is queued/pending/waiting; re-evaluate next tick"
    elif [ "$DRY" = 1 ]; then log "would start sync ($reason)"
    else
        out="$(gh workflow run sync.yml -R "$FORK_REPO" --ref main 2>&1)" || fail "gh workflow run: $out"
        echo "$want $now" > "$STATE"
        log "started sync ($reason)"
    fi
fi
# The trigger works again: a later failure is told again.
[ "$DRY" = 1 ] || sed -i '' '/^kick-failed$/d' "$ALERTED"

behind="$(gh api "repos/$FORK_REPO/compare/${UPSTREAM_REPO%%/*}:main...main" --jq .behind_by 2>&1)" || fail "compare: $behind"
[ "$behind" = 0 ] && exit 0
committed="$(gh api "repos/$UPSTREAM_REPO/commits/$upstream_main" --jq .commit.committer.date 2>&1)" || fail "commit date: $committed"
age_min=$(( (now - $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$committed" +%s)) / 60 ))
[ "$age_min" -lt "$LAG_ALERT_MIN" ] && exit 0
open="$(gh issue list -R "$FORK_REPO" --state open --label notchcast-sync --json number --jq length 2>&1)" || fail "issues: $open"
[ "$open" = 0 ] || exit 0
log "main is $behind behind upstream ${upstream_main:0:8}, committed $age_min min ago, and no notchcast-sync issue is open"
alert_once "lag-$upstream_main" "upstream ${upstream_main:0:8} is not in our main $age_min min after it was committed, and no sync issue explains it. https://github.com/$FORK_REPO/actions/workflows/sync.yml"
