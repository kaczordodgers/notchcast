#!/bin/bash
# One landing hold for everyone who lands Notchcast, on any Mac: the repository variable LANDING_HOLD,
# "<owner> <expiry, epoch seconds>[ auto]". While it has not expired, land.sh lands only the owner's PR: the owner is a PR
# number, or a name the lander passes in NOTCHCAST_LAND_AS. It expires by itself. land.sh takes an `auto` hold for its
# own PR at its start (so the first lander is never refused at the end) and releases it at exit; set refuses over another
# owner's live hold unless --handover.
#   notchcast/hold.sh set [--handover] <owner> <minutes> | release | show
# land.sh sources this file for check_hold, hold_claim and hold_renew_claimed; the caller defines refuse.
source "$(dirname "${BASH_SOURCE[0]}")/config.env"
hold_repo=$FORK_REPO

# Prints the hold, or nothing when there is none; fails when it cannot be read.
hold_read() {
    local out
    if out=$(gh variable get LANDING_HOLD -R "$hold_repo" 2>&1); then
        echo "$out"
    elif [[ "$out" != *'was not found'* ]]; then
        echo "$out" >&2
        return 1
    fi
}

hold_time() { date -r "$1" '+%H:%M %Z'; }

# Splits a hold into owner, until and auto (the optional third token, set by land.sh itself); fails on anything else.
hold_parse() {
    auto=
    [[ "$1" =~ ^([A-Za-z0-9._-]+)\ ([1-9][0-9]*)(\ auto)?$ ]] && owner=${BASH_REMATCH[1]} until=${BASH_REMATCH[2]} auto=${BASH_REMATCH[3]:+auto}
}

# Sets the caller's owner, until and auto from the live hold; fails when there is none or it has expired.
hold_live() {
    local hold
    hold=$(hold_read) || refuse 'cannot read the landing hold (gh variable get LANDING_HOLD); try again'
    [ -n "$hold" ] || return 1
    hold_parse "$hold" || refuse "malformed landing hold '$hold'; replace it: notchcast/hold.sh set or release"
    [ "$until" -gt "$(date +%s)" ]
}

hold_refuse_foreign() { refuse "landing is held for $owner until $(hold_time "$until"); it expires by itself, or: notchcast/hold.sh release"; }

# Refuses unless the hold is absent, expired, or owned by PR $1 or by NOTCHCAST_LAND_AS.
check_hold() {
    local owner until auto
    hold_live || return 0
    [ "$owner" = "$1" ] || [ "$owner" = "${NOTCHCAST_LAND_AS:-}" ] || hold_refuse_foreign
}

# land.sh, at its start, for the PRs "$@": refuses under a foreign live hold; under its own, takes nothing (hold_pr is
# the one PR a hold names, empty under NOTCHCAST_LAND_AS); otherwise takes an auto hold for PR $1, so a hold set during
# its harnesses cannot refuse it at the end. hold_release_claimed gives it back.
hold_claimed=
hold_pr=
hold_claim() {
    local owner until auto value minutes=${NOTCHCAST_LAND_HOLD_MINUTES:-150} current pr
    [[ "$minutes" =~ ^[0-9]+$ ]] || refuse "NOTCHCAST_LAND_HOLD_MINUTES must be a number, not '$minutes'"
    if hold_live; then
        [ "$owner" != "${NOTCHCAST_LAND_AS:-}" ] || return 0
        for pr in "$@"; do
            [ "$owner" != "$pr" ] || { hold_pr=$pr; return 0; }
        done
        hold_refuse_foreign
    fi
    value="$1 $(($(date +%s) + 10#$minutes * 60)) auto"
    hold_claimed=$value  # before the set: a failed set may still have saved it, and exit must release it
    gh variable set LANDING_HOLD -R "$hold_repo" --body "$value" > /dev/null || refuse 'cannot set the landing hold; try again'
    current=$(hold_read) || refuse 'cannot read the landing hold (gh variable get LANDING_HOLD); try again'
    [ "$current" = "$value" ] || refuse 'another lander took the landing hold first; try again'
}

# land.sh, before each push: restarts its own auto hold's clock so a long run cannot outlive it; leaves any other hold to
# check_hold. Warns rather than refuses when the hold cannot be read or set.
hold_renew_claimed() {
    local current value
    [ -n "$hold_claimed" ] || return 0
    if ! current=$(hold_read 2> /dev/null); then
        echo 'WARN: cannot read the landing hold to renew it' >&2
        return 0
    fi
    [ "$current" = "$hold_claimed" ] || return 0
    value="${hold_claimed%% *} $(($(date +%s) + 10#${NOTCHCAST_LAND_HOLD_MINUTES:-150} * 60)) auto"
    hold_claimed=$value
    gh variable set LANDING_HOLD -R "$hold_repo" --body "$value" > /dev/null || echo 'WARN: could not renew the landing hold' >&2
}

# Deletes the hold only if it is still exactly what hold_claim wrote; never one set or extended since.
hold_release_claimed() {
    local current
    [ -n "$hold_claimed" ] || return 0
    if ! current=$(hold_read 2> /dev/null); then
        echo 'WARN: cannot read the landing hold to release it; it expires by itself' >&2
    elif [ "$current" = "$hold_claimed" ]; then
        gh variable delete LANDING_HOLD -R "$hold_repo" > /dev/null || echo 'WARN: could not release the landing hold; it expires by itself' >&2
    fi
    hold_claimed=
}

# local-ci.sh: succeeds when PR $1 (or NOTCHCAST_LAND_AS) owns an unexpired hold, so its build goes first; fails when
# there is none or it is land.sh's own auto hold (one landing must not stall every other PR's build); waits while anyone
# else holds it, or while it cannot be read or parsed.
hold_turn() {
    local hold owner until auto said=
    while :; do
        owner= until=
        if hold=$(hold_read); then
            [ -n "$hold" ] || return 1
            if hold_parse "$hold"; then
                [ "$until" -gt "$(date +%s)" ] || return 1
                [ -z "$auto" ] || return 1
                [ "$owner" != "$1" ] && [ "$owner" != "${NOTCHCAST_LAND_AS:-}" ] || return 0
            fi
        fi
        if [ -z "$said" ] && [ -n "$owner" ]; then echo "local CI waits: landing is held for $owner until $(hold_time "$until")"
        elif [ -z "$said" ]; then echo 'local CI waits: the landing hold is unreadable or malformed'; fi
        said=1
        sleep "${NOTCHCAST_HOLD_POLL_SECONDS:-30}"
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    refuse() { echo "REFUSED: $*" >&2; exit 1; }
    usage() { echo 'usage: notchcast/hold.sh set [--handover] <owner> <minutes> | release | show' >&2; exit 2; }
    case "${1:-}:$#" in
        set:3|set:4)
            handover=
            if [ "$2" = --handover ]; then handover=1; shift; fi
            [ "$#" -eq 3 ] || usage
            [[ "$2" =~ ^[A-Za-z0-9._-]+$ && "$3" =~ ^[0-9]+$ ]] || usage
            if [ -z "$handover" ]; then
                hold=$(hold_read) || refuse 'cannot read the landing hold (gh variable get LANDING_HOLD); try again'
                if hold_parse "$hold" && [ "$until" -gt "$(date +%s)" ] && [ "$owner" != "$2" ]; then
                    refuse "landing is held for $owner until $(hold_time "$until"); it expires by itself, or take it over: notchcast/hold.sh set --handover $2 $3"
                fi
            fi
            until=$(($(date +%s) + 10#$3 * 60))
            gh variable set LANDING_HOLD -R "$hold_repo" --body "$2 $until"
            echo "landing held for $2 until $(hold_time "$until")" ;;
        release:1) gh variable delete LANDING_HOLD -R "$hold_repo" ;;
        show:1)
            hold=$(hold_read)
            if [ -z "$hold" ]; then echo 'no landing hold'
            elif ! hold_parse "$hold"; then echo "malformed landing hold '$hold' (land.sh refuses)"; exit 1
            elif [ "$until" -le "$(date +%s)" ]; then echo "no landing hold ($owner expired)"
            else echo "landing held for $owner until $(hold_time "$until")"; fi ;;
        *) usage ;;
    esac
fi
