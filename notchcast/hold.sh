#!/bin/bash
# One landing hold for everyone who lands Notchcast, on any Mac: the repository variable LANDING_HOLD,
# "<owner> <expiry, epoch seconds>". While it has not expired, land.sh lands only the owner's PR: the owner is a PR
# number, or a name the lander passes in NOTCHCAST_LAND_AS. It expires by itself.
#   notchcast/hold.sh set <owner> <minutes> | release | show
# land.sh sources this file for check_hold; the caller defines refuse.
hold_repo=kaczordodgers/notchcast

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

# Refuses unless the hold is absent, expired, or owned by PR $1 or by NOTCHCAST_LAND_AS.
check_hold() {
    local hold owner until
    hold=$(hold_read) || refuse 'cannot read the landing hold (gh variable get LANDING_HOLD); try again'
    read -r owner until <<< "$hold"
    [ -n "$owner" ] && [ "${until:-0}" -gt "$(date +%s)" ] || return 0
    [ "$owner" = "$1" ] || [ "$owner" = "${NOTCHCAST_LAND_AS:-}" ] \
        || refuse "landing is held for $owner until $(hold_time "$until"); it expires by itself, or: notchcast/hold.sh release"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    usage() { echo 'usage: notchcast/hold.sh set <owner> <minutes> | release | show' >&2; exit 2; }
    case "${1:-}:$#" in
        set:3)
            [[ "$2" =~ ^[A-Za-z0-9._-]+$ && "$3" =~ ^[0-9]+$ ]] || usage
            until=$(($(date +%s) + $3 * 60))
            gh variable set LANDING_HOLD -R "$hold_repo" --body "$2 $until"
            echo "landing held for $2 until $(hold_time "$until")" ;;
        release:1) gh variable delete LANDING_HOLD -R "$hold_repo" ;;
        show:1)
            read -r owner until <<< "$(hold_read)"
            if [ -z "$owner" ]; then echo 'no landing hold'
            elif [ "${until:-0}" -le "$(date +%s)" ]; then echo "no landing hold ($owner expired)"
            else echo "landing held for $owner until $(hold_time "$until")"; fi ;;
        *) usage ;;
    esac
fi
