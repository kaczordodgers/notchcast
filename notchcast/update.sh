#!/bin/bash
# Notchcast updater: install the newest kaczordodgers/notchcast release at /Applications/Notchcast.app and have the
# notchcast.app LaunchAgent restart it. Runs from launchd (notchcast.update) and from install-launchd.sh (first install).
# It installs only a build with our bundle id (BUNDLE_ID), the release's version and our leaf certificate (SIGN_SHA1),
# and only when nothing is installed yet, the release is newer, or the installed copy is not ours.
# It replaces only the .app bundle: the old one goes to the Trash; settings, data and Keychain items are never touched.
# The in-app updater stays inert for app.notchcast (ReleaseChannel: development), so this is the update path.
# Usage: update.sh [--dry-run]
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin"

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
APP="/Applications/$APP_NAME.app"
log() { printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*"; }

leaf_sha1() {
    local d
    d="$(mktemp -d)"
    codesign -d --extract-certificates="$d/c" "$1" 2>/dev/null || { rm -rf "$d"; return 0; }
    shasum -a 1 "$d/c0" | awk '{print toupper($1)}'
    rm -rf "$d"
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true; }

# Tell Chad once per failed sync input (a new refs/notchcast-failed/* ref; GitHub also emails the failed run).
# Only where chad-opus exists (the MBA), so one Mac sends. The first run records the existing failures silently.
alert_failures() {
    command -v chad-opus >/dev/null || return 0
    local seen="$HOME/Library/Application Support/notchcast/alerted-failures" refs ref
    refs="$(git ls-remote "https://github.com/$FORK_REPO.git" 'refs/notchcast-failed/*' | cut -f2 | sort)"
    mkdir -p "$(dirname "$seen")"
    if [ ! -f "$seen" ]; then [ "$DRY" = 1 ] || printf '%s\n' "$refs" > "$seen"; return 0; fi
    for ref in $(comm -13 "$seen" <(printf '%s\n' "$refs")); do
        if [ "$DRY" = 1 ]; then log "would alert: $ref"; continue; fi
        printf 'Notchcast sync failed: %s. Nothing was published; it retries when upstream or main changes. Runs: https://github.com/%s/actions/workflows/sync.yml\n' \
            "${ref#refs/notchcast-failed/}" "$FORK_REPO" | chad-opus ping failure - >/dev/null
        echo "$ref" >> "$seen"
        log "alerted Chad: $ref"
    done
}
alert_failures || log "failure alert check failed; retried next run"

INSTALLED="" OURS=0
if [ -d "$APP" ]; then
    [ "$(plist "$APP" CFBundleIdentifier)" = "$BUNDLE_ID" ] || { log "$APP is not $BUNDLE_ID; not touching it"; exit 0; }
    INSTALLED="$(plist "$APP" CFBundleShortVersionString)"
    [ "$(leaf_sha1 "$APP")" = "$SIGN_SHA1" ] && OURS=1
fi

# Versions compare as (x, y, z, stable-after-beta, beta number); never install a lower version than the installed one.
VKEY='def vkey: ltrimstr("v") | capture("^(?<a>[0-9]+)[.](?<b>[0-9]+)[.](?<c>[0-9]+)(-[a-z]+[.](?<n>[0-9]+))?$")
    | [(.a|tonumber), (.b|tonumber), (.c|tonumber), (if .n then 0 else 1 end), ((.n // "0")|tonumber)];'
TAG="$(gh release list -R "$FORK_REPO" -L 30 --json tagName,isDraft,isPrerelease \
    --jq "$VKEY [.[] | select(.isDraft | not) | select(.tagName | test(\"^v[0-9]+[.][0-9]+[.][0-9]+(-[a-z]+[.][0-9]+)?$\"))]
          | sort_by(.tagName | vkey) | last | .tagName // empty")"
[ -n "$TAG" ] || { log "no $FORK_REPO release yet"; exit 0; }
WANT="${TAG#v}"
if [ -z "$INSTALLED" ]; then CMP=newer; else CMP="$(jq -nr --arg want "$WANT" --arg have "$INSTALLED" "$VKEY"' if ($want|vkey) > ($have|vkey) then "newer" elif ($want|vkey) == ($have|vkey) then "same" else "older" end')"; fi
[ -n "$CMP" ] || { log "cannot compare versions '$WANT' and '$INSTALLED'; not installing"; exit 0; }
if [ "$CMP" = older ] || { [ "$CMP" = same ] && [ "$OURS" = 1 ]; }; then
    log "nothing to install: newest release $WANT, installed $INSTALLED ($([ "$OURS" = 1 ] && echo ours || echo "not ours"))"
    exit 0
fi
log "installing $TAG over ${INSTALLED:-nothing} ($([ "$OURS" = 1 ] && echo ours || echo "not ours"))"
[ "$DRY" = 1 ] && exit 0

WORK="$(mktemp -d "${TMPDIR:-/tmp}/notchcast-update.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
gh release download "$TAG" -R "$FORK_REPO" -D "$WORK" -p "$APP_NAME-${WANT}.zip"
mkdir "$WORK/x"
ditto -x -k "$WORK/$APP_NAME-${WANT}.zip" "$WORK/x"
NEW="$(find "$WORK/x" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$NEW" ] || { log "no app in the release zip"; exit 1; }
xattr -dr com.apple.quarantine "$NEW" 2>/dev/null || true
codesign --verify --deep --strict "$NEW"
[ "$(plist "$NEW" CFBundleIdentifier)" = "$BUNDLE_ID" ] || { log "bundle id mismatch; refusing"; exit 1; }
[ "$(plist "$NEW" CFBundleShortVersionString)" = "$WANT" ] || { log "version mismatch; refusing"; exit 1; }
[ "$(leaf_sha1 "$NEW")" = "$SIGN_SHA1" ] || { log "not signed by $SIGN_IDENTITY; refusing"; exit 1; }

# The running app keeps running from its moved bundle until the agent restarts it on the new one.
# The old bundle goes to the Trash, never rm; a failed copy is moved aside and the old bundle put back.
TRASHED=""
if [ -d "$APP" ]; then
    TRASHED="$HOME/.Trash/$APP_NAME $INSTALLED $(date +%Y%m%d-%H%M%S).app"
    mv "$APP" "$TRASHED"
fi
if ! ditto "$NEW" "$APP"; then
    [ -e "$APP" ] && mv "$APP" "$HOME/.Trash/$APP_NAME failed copy $(date +%Y%m%d-%H%M%S).app"
    [ -z "$TRASHED" ] || mv "$TRASHED" "$APP"
    log "copy failed; previous state restored"
    exit 1
fi
log "installed $TAG at $APP${TRASHED:+; previous app moved to $TRASHED}"
# The app is started only by its LaunchAgent (install-launchd.sh app), never here.
AGENT="gui/$(id -u)/notchcast.app"
if launchctl print "$AGENT" >/dev/null 2>&1; then
    launchctl kickstart -k "$AGENT"
    log "restarted $AGENT"
else
    log "$AGENT is not loaded; the new app starts at the next start of the agent (install-launchd.sh app)"
fi
