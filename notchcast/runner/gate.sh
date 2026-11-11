#!/bin/bash
# Every minute on a runner Mac, and at each job start. Usage: gate.sh <host> <owner/repo>
#   Publishes how many of this Mac's runners are idle as the repository variable NOTCHCAST_IDLE_<HOST>, which
#   notchcast/runner/route.py reads. While the admit command (install.sh --gate) refuses, it publishes 0 and,
#   from the second refusal on, stops the runners that have no job; it starts those again once admitted.
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
        if launchctl bootout "$DOMAIN/$label"; then loaded=0; touch "$dir.stopped"; say "refused: stopped $name"; fi
    # Only a runner this gate stopped: one booted out by hand, to remove it, stays out.
    elif [ "$admitted" = 1 ] && [ "$loaded" = 0 ] && [ -e "$dir.stopped" ]; then
        if launchctl bootstrap "$DOMAIN" "$HOME/Library/LaunchAgents/$label.plist"; then loaded=1; say "admitted: started $name"; fi
    fi
    [ "$loaded" = 0 ] || rm -f "$dir.stopped"
    if [ "$loaded" = 1 ] && [ "$busy" = 0 ]; then idle=$((idle + 1)); fi
done
if [ "$admitted" = 0 ]; then
    [ -e "$ROOT/refused" ] || say "refused: taking no new job"
    touch "$ROOT/refused"
    idle=0
else
    rm -f "$ROOT/refused"
fi

# Every run publishes: route.py takes a count older than 150 s for a Mac that is asleep. The log gets changes only.
state="idle $idle"
error=$(gh variable set "NOTCHCAST_IDLE_$(echo "$HOST" | tr '[:lower:]' '[:upper:]')" --repo "$REPO" --body "$idle $(date +%s)" 2>&1 >/dev/null) \
    || state="could not publish idle $idle: $error"
[ "$(cat "$ROOT/published" 2>/dev/null)" = "$state" ] || say "$state"
echo "$state" > "$ROOT/published"
