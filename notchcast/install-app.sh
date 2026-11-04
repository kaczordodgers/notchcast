#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
APP="${NOTCHCAST_APP:-/Applications/$APP_NAME.app}"
AGENT="gui/$(id -u)/${NOTCHCAST_AGENT:-notchcast.app}"
WATCH="${NOTCHCAST_WATCH_SECONDS:-60}"
TRASH="${NOTCHCAST_TRASH:-$HOME/.Trash}"
PREVIOUS="$HOME/Library/Application Support/notchcast/previous/$APP_NAME.app"
if [ -n "${NOTCHCAST_APP:-}" ]; then PREVIOUS="$(dirname "$APP")/previous/$APP_NAME.app"; fi
version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null || echo unknown; }
log() { printf '%s\n' "$*"; }
FINAL='nothing (installation interrupted)'
trap 'log "left running: $FINAL"' EXIT
[[ "$WATCH" =~ ^[0-9]+$ ]] || { FINAL='nothing (invalid watch seconds)'; exit 2; }
# One install at a time: a second one exits 75 and touches nothing.
if [ -z "${NOTCHCAST_INSTALL_LOCKED:-}" ] && [ -d "${1:-}/Contents" ]; then
    mkdir -p "$(dirname "$PREVIOUS")"
    trap - EXIT
    NOTCHCAST_INSTALL_LOCKED=1 exec lockf -k -t 0 "$(dirname "$PREVIOUS")/install.lock" "$0" "$@"
fi
[ "$#" = 1 ] && [ -d "$1/Contents" ] || { FINAL='nothing (usage: install-app.sh <new.app>)'; exit 2; }
NEW_VERSION="$(version "$1")"
trash() {
    local target
    target="$TRASH/$APP_NAME $2 $(date +%Y%m%d-%H%M%S)-$$.app"
    mkdir -p "$TRASH"
    mv "$1" "$target"
}
watch_agent() {
    local output state pid runs first_pid='' first_runs='' start=$SECONDS
    while :; do
        output="$(launchctl print "$AGENT" 2>/dev/null)" || return 1
        state="$(awk '$1 == "state" && $2 == "=" {print $3; exit}' <<< "$output")"
        pid="$(awk '$1 == "pid" && $2 == "=" {print $3; exit}' <<< "$output")"
        runs="$(awk '$1 == "runs" && $2 == "=" {print $3; exit}' <<< "$output")"
        if [ "$state" != running ]; then
            if grep -q 'last exit code =' <<< "$output"; then return 1; fi
        elif [ -z "$first_pid" ]; then
            [ -n "$pid" ] && [ -n "$runs" ] || return 1
            first_pid="$pid"; first_runs="$runs"
        else
            [ "$pid" = "$first_pid" ] && [ "$runs" = "$first_runs" ] || return 1
        fi
        if (( SECONDS - start >= WATCH )); then
            [ "$state" = running ] && [ -n "$first_pid" ]
            return
        fi
        sleep 1
    done
}
restart_agent() {
    local client start=$SECONDS
    launchctl kickstart -k "$AGENT" &
    client=$!
    while kill -0 "$client" 2>/dev/null; do
        # kickstart -k waits out the agent's ThrottleInterval and the old app's exit.
        if (( SECONDS - start >= 45 )); then
            kill "$client" 2>/dev/null || true
            wait "$client" 2>/dev/null || true
            return 1
        fi
        sleep 1
    done
    wait "$client"
}
LOADED=0
if launchctl print "$AGENT" >/dev/null 2>&1; then LOADED=1; fi
mkdir -p "$(dirname "$PREVIOUS")" "$(dirname "$APP")"
HAD_PREVIOUS=0
if [ -e "$APP" ]; then
    if [ -e "$PREVIOUS" ]; then trash "$PREVIOUS" "previous $(version "$PREVIOUS")"; fi
    mv "$APP" "$PREVIOUS"
    HAD_PREVIOUS=1
elif [ -e "$PREVIOUS" ]; then
    HAD_PREVIOUS=1
fi
if ditto "$1" "$APP"; then
    if [ "$LOADED" = 0 ]; then
        FINAL="nothing (agent is not loaded; check skipped; installed $NEW_VERSION)"
        exit 0
    fi
    if restart_agent && watch_agent; then
        FINAL="$NEW_VERSION (new)"
        exit 0
    fi
fi
log "installation did not stay alive; restoring previous app"
if [ -e "$APP" ]; then trash "$APP" "failed $NEW_VERSION"; fi
# The agent stays loaded on every path: a bootout would keep the app down until the next login.
if [ "$HAD_PREVIOUS" = 1 ]; then
    mv "$PREVIOUS" "$APP"
    if [ "$LOADED" = 0 ]; then
        FINAL="nothing (agent is not loaded; restored $(version "$APP"))"
    elif restart_agent && watch_agent; then
        FINAL="$(version "$APP") (previous)"
    else
        FINAL="nothing (restored $(version "$APP") did not stay alive)"
    fi
else
    FINAL='nothing (no previous app to restore)'
fi
exit 1
