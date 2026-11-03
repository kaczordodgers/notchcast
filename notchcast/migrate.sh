#!/bin/bash
# One-time copy of the old Tinycast data (OLD_BUNDLE_ID) to Notchcast (BUNDLE_ID), run by install-launchd.sh before
# Notchcast first starts. Each part is copied only when its destination is still empty, and never again after the
# first run on this Mac (marker below). The old preferences, folders and Keychain items are only read, never changed.
# Keychain secrets are not copied: they are keyed by bundle id and copying them means reading them.
# Usage: migrate.sh [--dry-run]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
log() { printf '%s migrate: %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*"; }
do_or_say() { if [ "$DRY" = 1 ]; then log "would: $*"; else "$@"; fi; }

MARKER="$HOME/Library/Application Support/notchcast/migrated-from-$OLD_BUNDLE_ID"
[ ! -e "$MARKER" ] || { log "already migrated on this Mac ($MARKER)"; exit 0; }
OLD_SUPPORT="$HOME/Library/Application Support/$OLD_BUNDLE_ID"
NEW_SUPPORT="$HOME/Library/Application Support/$BUNDLE_ID"
OLD_SETTINGS="$HOME/.config/$OLD_CONFIG_DIR/settings.json"
# AppPaths.configFolderName: an id outside com.tinycast.app uses the id itself as the folder name.
NEW_SETTINGS="$HOME/.config/$BUNDLE_ID/settings.json"

# Both apps must be stopped, so the SQLite files are consistent and nothing writes the new domain first.
if pgrep -f "^$OLD_APP/Contents/MacOS/" >/dev/null; then
    do_or_say osascript -e "tell application id \"$OLD_BUNDLE_ID\" to quit"
    [ "$DRY" = 1 ] || for _ in $(seq 1 30); do pgrep -f "^$OLD_APP/Contents/MacOS/" >/dev/null || break; sleep 0.5; done
    [ "$DRY" = 1 ] || ! pgrep -f "^$OLD_APP/Contents/MacOS/" >/dev/null || { log "old app did not quit; nothing migrated"; exit 1; }
fi
! pgrep -f "^/Applications/$APP_NAME.app/Contents/MacOS/" >/dev/null || { log "$APP_NAME is running; nothing migrated"; exit 1; }

if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    log "preferences: $BUNDLE_ID already has some; kept"
elif defaults read "$OLD_BUNDLE_ID" >/dev/null 2>&1; then
    if [ "$DRY" = 1 ]; then log "would: defaults export $OLD_BUNDLE_ID - | defaults import $BUNDLE_ID -"
    else defaults export "$OLD_BUNDLE_ID" - | defaults import "$BUNDLE_ID" -; log "preferences: copied"; fi
fi
if [ -e "$NEW_SUPPORT" ]; then
    log "data: $NEW_SUPPORT exists; kept"
elif [ -d "$OLD_SUPPORT" ]; then
    do_or_say ditto "$OLD_SUPPORT" "$NEW_SUPPORT"; [ "$DRY" = 1 ] || log "data: copied $(du -sh "$OLD_SUPPORT" | cut -f1)"
fi
if [ -e "$NEW_SETTINGS" ]; then
    log "settings: $NEW_SETTINGS exists; kept"
elif [ -f "$OLD_SETTINGS" ]; then
    do_or_say mkdir -p "$(dirname "$NEW_SETTINGS")"
    do_or_say cp -p "$OLD_SETTINGS" "$NEW_SETTINGS"; [ "$DRY" = 1 ] || log "settings: copied"
fi
[ "$DRY" = 1 ] || { mkdir -p "$(dirname "$MARKER")"; date > "$MARKER"; }
log "done"
