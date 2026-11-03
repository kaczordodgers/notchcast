#!/bin/bash
# Notchcast updater: install the newest kaczordodgers/notchcast release of the installed app's channel and have its LaunchAgent restart it.
# Runs from launchd (notchcast.update). It installs only a build whose bundle id matches the installed
# app and whose leaf certificate is SIGN_SHA1, and only when the installed copy is not ours yet or its version differs
# from the newest release, then restarts notchcast.app. Once ours is installed, the in-app updater (the release feed commit) also takes our releases.
# It replaces only the .app bundle: the old one goes to the Trash; settings, data and Keychain items are never touched.
# Usage: update.sh [--dry-run] [app path]
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin"

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
APP="${1:-/Applications/Tinycast Beta.app}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
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

[ -d "$APP" ] || { log "no app at $APP; nothing to update"; exit 0; }
BUNDLE_ID="$(plist "$APP" CFBundleIdentifier)"
INSTALLED="$(plist "$APP" CFBundleShortVersionString)"
case "$BUNDLE_ID" in
    com.tinycast.app.beta) PRE=true ;;
    com.tinycast.app) PRE=false ;;
    *) log "unknown bundle id '$BUNDLE_ID' at $APP; not touching it"; exit 0 ;;
esac
OURS=0
[ "$(leaf_sha1 "$APP")" = "$SIGN_SHA1" ] && OURS=1

# Versions compare as (x, y, z, stable-after-beta, beta number); never install a lower version than the installed one.
VKEY='def vkey: ltrimstr("v") | capture("^(?<a>[0-9]+)[.](?<b>[0-9]+)[.](?<c>[0-9]+)(-[a-z]+[.](?<n>[0-9]+))?$")
    | [(.a|tonumber), (.b|tonumber), (.c|tonumber), (if .n then 0 else 1 end), ((.n // "0")|tonumber)];'
TAG="$(gh release list -R "$FORK_REPO" -L 30 --json tagName,isDraft,isPrerelease \
    --jq "$VKEY [.[] | select(.isDraft | not) | select(.isPrerelease == $PRE) | select(.tagName | test(\"^v[0-9]+[.][0-9]+[.][0-9]+(-[a-z]+[.][0-9]+)?$\"))]
          | sort_by(.tagName | vkey) | last | .tagName // empty")"
[ -n "$TAG" ] || { log "no $FORK_REPO release for this channel yet"; exit 0; }
WANT="${TAG#v}"
CMP="$(jq -nr --arg want "$WANT" --arg have "$INSTALLED" "$VKEY"' if ($want|vkey) > ($have|vkey) then "newer" elif ($want|vkey) == ($have|vkey) then "same" else "older" end')"
[ -n "$CMP" ] || { log "cannot compare versions '$WANT' and '$INSTALLED'; not installing"; exit 0; }
if [ "$CMP" = older ] || { [ "$CMP" = same ] && [ "$OURS" = 1 ]; }; then
    log "nothing to install: newest release $WANT, installed $INSTALLED ($([ "$OURS" = 1 ] && echo ours || echo "not ours"))"
    exit 0
fi
log "installing $TAG over $INSTALLED ($([ "$OURS" = 1 ] && echo ours || echo "not ours"))"
[ "$DRY" = 1 ] && exit 0

WORK="$(mktemp -d "${TMPDIR:-/tmp}/notchcast-update.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
gh release download "$TAG" -R "$FORK_REPO" -D "$WORK" -p "Tinycast-${WANT}.zip"
mkdir "$WORK/x"
ditto -x -k "$WORK/Tinycast-${WANT}.zip" "$WORK/x"
NEW="$(find "$WORK/x" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$NEW" ] || { log "no app in the release zip"; exit 1; }
xattr -dr com.apple.quarantine "$NEW" 2>/dev/null || true
codesign --verify --deep --strict "$NEW"
[ "$(plist "$NEW" CFBundleIdentifier)" = "$BUNDLE_ID" ] || { log "bundle id mismatch; refusing"; exit 1; }
[ "$(plist "$NEW" CFBundleShortVersionString)" = "$WANT" ] || { log "version mismatch; refusing"; exit 1; }
[ "$(leaf_sha1 "$NEW")" = "$SIGN_SHA1" ] || { log "not signed by $SIGN_IDENTITY; refusing"; exit 1; }

# The running app keeps running from its moved bundle until the agent restarts it on the new one.
# The old bundle goes to the Trash, never rm; a failed copy is moved aside and the old bundle put back.
TRASHED="$HOME/.Trash/$(basename "$APP" .app) $INSTALLED $(date +%Y%m%d-%H%M%S).app"
mv "$APP" "$TRASHED"
if ! ditto "$NEW" "$APP"; then
    [ -e "$APP" ] && mv "$APP" "$TRASHED.failed-copy.app"
    mv "$TRASHED" "$APP"
    log "copy failed; previous version restored"
    exit 1
fi
log "installed $TAG at $APP; previous app moved to $TRASHED"
# The app is started only by its LaunchAgent (install-launchd.sh app), never here.
AGENT="gui/$(id -u)/notchcast.app"
if launchctl print "$AGENT" >/dev/null 2>&1; then
    launchctl kickstart -k "$AGENT"
    log "restarted $AGENT"
else
    log "$AGENT is not loaded; the new app starts at the next start of the agent (install-launchd.sh app)"
fi
