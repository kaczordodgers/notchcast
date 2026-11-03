#!/bin/bash
# Notchcast updater: install the newest kaczordodgers/notchcast release at /Applications/Notchcast.app and have the
# notchcast.app LaunchAgent restart it. Runs from launchd (notchcast.update) and from install-launchd.sh (first install).
# It installs only a build with our bundle id (BUNDLE_ID), the release's version and our leaf certificate (SIGN_SHA1),
# and only when nothing is installed yet, the release is newer, or the installed copy is not ours.
# It replaces only the .app bundle: the old one goes to the Trash; settings, data and Keychain items are never touched.
# The in-app updater stays inert for app.notchcast (ReleaseChannel: development), so this is the update path.
# Leads run notchcast/update.sh --install at each milestone end on both Macs, even with automatic updates off.
# Usage: update.sh [--install] [--dry-run] (either order)
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin"

DRY=0
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --install) INSTALL=1 ;;
        *) echo "Usage: update.sh [--install] [--dry-run] (either order)" >&2; exit 2 ;;
    esac
done
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

# The sync reports through issues on the fork (notchcast/ci.py): notchcast-sync, -main and -release are failures, one
# open issue per kind whose cause marker changes only with a new cause; notchcast-design asks for a docs refresh.
# Only where chad-opus exists (the MBA), so one Mac acts: Chad is told once per issue and cause, and each design
# issue becomes one Todoist task (label notchcast, Backlog) and is closed.
TODOIST_PROJECT=id:6h2GM7vHJxfxj6Xc TODOIST_BACKLOG=id:6hXmwWJvMr4gV736
alert_issues() {
    command -v chad-opus >/dev/null || return 0
    local seen="$HOME/Library/Application Support/notchcast/alerted-issues" issues key n
    mkdir -p "$(dirname "$seen")"; touch "$seen"
    issues="$(gh issue list -R "$FORK_REPO" --state open --limit 50 --json number,title,url,body,labels \
        --jq '.[] | select(any(.labels[]; .name == "notchcast-sync" or .name == "notchcast-main" or .name == "notchcast-release"))
              | [(.number|tostring) + ":" + ((.body | capture("<!-- cause: (?<c>.*) -->").c) // .title), .title, .url] | @tsv')"
    while IFS=$'\t' read -r key title url; do
        [ -n "$key" ] && ! grep -qxF "$key" "$seen" || continue
        if [ "$DRY" = 1 ]; then log "would alert: $title"; continue; fi
        printf 'Notchcast: %s. Nothing was pushed or published. %s\n' "$title" "$url" | chad-opus ping failure - >/dev/null \
            || { log "ping for $title failed; retried next run"; return 1; }
        echo "$key" >> "$seen"
        log "alerted Chad: $title"
    done <<< "$issues"
    for n in $(gh issue list -R "$FORK_REPO" --state open --label notchcast-design --json number --jq '.[].number'); do
        if [ "$DRY" = 1 ]; then log "would add a Todoist task for design issue #$n"; continue; fi
        local body task
        body="$(gh issue view "$n" -R "$FORK_REPO" --json body,url --jq '.body + "\n" + .url')"
        task="$(chad-opus td task add "Refresh notchcast/docs/design-system.md" --project "$TODOIST_PROJECT" \
            --section "$TODOIST_BACKLOG" --labels notchcast --description "$body" --json | jq -r '.id // empty')"
        [ -n "$task" ] || { log "Todoist task for design issue #$n not created; retried next run"; return 1; }
        # A failed close would make the next run add a second task.
        gh issue close "$n" -R "$FORK_REPO" --comment "Todoist task $task" >/dev/null \
            || { log "design issue #$n: Todoist task $task created but the issue is still open; close it by hand"; return 1; }
        log "design issue #$n -> Todoist task $task"
    done
}
alert_issues || log "issue check failed; retried next run"

# The app's own "Automatically check for updates" toggle (Settings > General) governs this updater too: off means no
# update is installed unless --install is passed. A missing key or file means on; a first install is not an update.
SETTINGS="$HOME/.config/$BUNDLE_ID/settings.json"
if [ "$INSTALL" = 0 ] && [ -d "$APP" ] && [ "$(jq -r '.general.automaticallyCheckForUpdates' "$SETTINGS" 2>/dev/null)" = false ]; then
    log "automatic updates are off in $APP_NAME settings (general.automaticallyCheckForUpdates in $SETTINGS); not installing"
    exit 0
fi

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
