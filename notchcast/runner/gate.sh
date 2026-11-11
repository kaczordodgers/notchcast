#!/bin/bash
# Every minute on a runner Mac, and at each job start. Usage: gate.sh <host> <owner/repo>
#   Publishes how many of this Mac's runners are idle as the repository variable NOTCHCAST_IDLE_<HOST>, which
#   notchcast/runner/route.py reads. While the admit command (install.sh --gate) refuses, it publishes 0 and,
#   from the second refusal on, stops the runners that have no job; it starts them again once admitted.
set -uo pipefail
HOST=$1 REPO=$2
ROOT="${NOTCHCAST_RUNNER_ROOT:-$HOME/agents/gh-runner}"
DOMAIN="gui/$(id -u)"
say() { echo "$(date -u +%FT%TZ) $*"; }

admitted=1
if [ -x "$ROOT/admit" ] && ! "$ROOT/admit" >/dev/null 2>&1; then admitted=0; fi
idle=0
for dir in "$ROOT/$HOST"-*/; do
    [ -f "$dir.runner" ] || continue
    name=$(basename "$dir")
    label="notchcast.runner.$name"
    busy=0 loaded=0
    if pgrep -f "${dir}bin/Runner.Worker" >/dev/null; then busy=1; fi
    if launchctl print "$DOMAIN/$label" >/dev/null 2>&1; then loaded=1; fi
    # shortcut: a job assigned between the pgrep and the bootout dies; drain through the runner if that ever happens.
    if [ "$admitted" = 0 ] && [ "$loaded" = 1 ] && [ "$busy" = 0 ] && [ -e "$ROOT/refused" ]; then
        if launchctl bootout "$DOMAIN/$label"; then loaded=0; say "refused: stopped $name"; fi
    elif [ "$admitted" = 1 ] && [ "$loaded" = 0 ]; then
        if launchctl bootstrap "$DOMAIN" "$HOME/Library/LaunchAgents/$label.plist"; then loaded=1; say "admitted: started $name"; fi
    fi
    if [ "$loaded" = 1 ] && [ "$busy" = 0 ]; then idle=$((idle + 1)); fi
done
if [ "$admitted" = 0 ]; then
    [ -e "$ROOT/refused" ] || say "refused: taking no new job"
    touch "$ROOT/refused"
    idle=0
else
    rm -f "$ROOT/refused"
fi

last=$(cat "$ROOT/published" 2>/dev/null || echo "none 0")
now=$(date +%s)
if [ "${last% *}" != "$idle" ] || [ $((now - ${last#* })) -ge 180 ]; then
    if gh variable set "NOTCHCAST_IDLE_$(echo "$HOST" | tr '[:lower:]' '[:upper:]')" --repo "$REPO" --body "$idle $now"; then
        echo "$idle $now" > "$ROOT/published"
        [ "${last% *}" = "$idle" ] || say "idle $idle"
    else
        say "could not publish idle $idle"
    fi
fi
