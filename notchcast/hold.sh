#!/bin/bash
# One landing hold for everyone who lands Notchcast, on any Mac: the repository variable LANDING_HOLD,
# "<owner> <expiry, epoch seconds>". While it has not expired, land.sh lands only the owner's PR: the owner is a PR
# number, or a name the lander passes in NOTCHCAST_LAND_AS. It expires by itself.
#   notchcast/hold.sh set <owner> <minutes> | release | show
# land.sh sources this file for check_hold; the caller defines refuse.
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

# Splits a hold into owner and until; fails on anything hold.sh set would not write.
hold_parse() { [[ "$1" =~ ^([A-Za-z0-9._-]+)\ ([1-9][0-9]*)$ ]] && owner=${BASH_REMATCH[1]} until=${BASH_REMATCH[2]}; }

# Refuses unless the hold is absent, expired, or owned by PR $1 or by NOTCHCAST_LAND_AS.
check_hold() {
    local hold owner until
    hold=$(hold_read) || refuse 'cannot read the landing hold (gh variable get LANDING_HOLD); try again'
    [ -n "$hold" ] || return 0
    hold_parse "$hold" || refuse "malformed landing hold '$hold'; replace it: notchcast/hold.sh set or release"
    [ "$until" -gt "$(date +%s)" ] || return 0
    [ "$owner" = "$1" ] || [ "$owner" = "${NOTCHCAST_LAND_AS:-}" ] \
        || refuse "landing is held for $owner until $(hold_time "$until"); it expires by itself, or: notchcast/hold.sh release"
}

# local-ci.sh: succeeds when PR $1 (or NOTCHCAST_LAND_AS) owns an unexpired hold, so its build goes first; fails when
# there is none; waits while anyone else holds it, or while it cannot be read or parsed.
hold_turn() {
    local hold owner until said=
    while :; do
        owner= until=
        if hold=$(hold_read); then
            [ -n "$hold" ] || return 1
            if hold_parse "$hold"; then
                [ "$until" -gt "$(date +%s)" ] || return 1
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
    usage() { echo 'usage: notchcast/hold.sh set <owner> <minutes> | release | show' >&2; exit 2; }
    case "${1:-}:$#" in
        set:3)
            [[ "$2" =~ ^[A-Za-z0-9._-]+$ && "$3" =~ ^[0-9]+$ ]] || usage
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
