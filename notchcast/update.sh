#!/bin/bash
# Notchcast updater: install the newest kaczordodgers/notchcast release at /Applications/Notchcast.app and have the
# notchcast.app LaunchAgent restart it. Runs from launchd (notchcast.update) and from install-launchd.sh (first install).
# It installs only a build with our bundle id (BUNDLE_ID), the release's version and our leaf certificate (SIGN_SHA1),
# and only when nothing is installed yet, the release is newer, or the installed copy is not ours.
# It replaces only the bundle, keeping one previous app for rollback; settings and data are never touched.
# The in-app updater stays inert for app.notchcast (ReleaseChannel: development), so this is the update path.
# Leads run notchcast/update.sh --install at each milestone end on both Macs, even with automatic updates off.
# Usage: update.sh [--install] [--retry] [--dry-run] (any order)
# Existing installs, including --install, wait for five idle minutes, deferring after 25 minutes.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin"

DRY=0
INSTALL=0
RETRY=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --install) INSTALL=1 ;;
        --retry) RETRY=1 ;;
        *) echo "Usage: update.sh [--install] [--retry] [--dry-run] (any order)" >&2; exit 2 ;;
    esac
done
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
APP="${NOTCHCAST_APP:-/Applications/$APP_NAME.app}"
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
# ~/.config/notchcast/private.env supplies NOTCHCAST_TODOIST_PROJECT and NOTCHCAST_TODOIST_BACKLOG.
if [ -f "$HOME/.config/notchcast/private.env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.config/notchcast/private.env"
fi
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
        if [ -z "${NOTCHCAST_TODOIST_PROJECT:-}" ] || [ -z "${NOTCHCAST_TODOIST_BACKLOG:-}" ]; then
            log "no private.env; design issue #$n left open"
            continue
        fi
        if [ "$DRY" = 1 ]; then log "would add a Todoist task for design issue #$n"; continue; fi
        local body task
        body="$(gh issue view "$n" -R "$FORK_REPO" --json body,url --jq '.body + "\n" + .url')"
        task="$(chad-opus td task add "Refresh notchcast/docs/design-system.md" --project "$NOTCHCAST_TODOIST_PROJECT" \
            --section "$NOTCHCAST_TODOIST_BACKLOG" --labels notchcast --description "$body" --json | jq -r '.id // empty')"
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

# Snapshot revisions sort after their mirror and before the next upstream version.
VKEY='def vkey: ltrimstr("v") | capture("^(?<a>[0-9]+)[.](?<b>[0-9]+)[.](?<c>[0-9]+)(-[a-z]+[.](?<n>[0-9]+))?([.]snapshot[.](?<s>[0-9]+))?$")
    | [(.a|tonumber), (.b|tonumber), (.c|tonumber), (if .n then 0 else 1 end), ((.n // "0")|tonumber), ((.s // "0")|tonumber)];'
TAG="$(gh release list -R "$FORK_REPO" -L 30 --json tagName,isDraft,isPrerelease \
    --jq "$VKEY [.[] | select(.isDraft | not) | select(.tagName | test(\"^v[0-9]+[.][0-9]+[.][0-9]+(-[a-z]+[.][0-9]+)?([.]snapshot[.][0-9]+)?$\"))]
          | sort_by(.tagName | vkey) | last | .tagName // empty")"
[ -n "$TAG" ] || { log "no $FORK_REPO release yet"; exit 0; }
WANT="${TAG#v}"
if [ -z "$INSTALLED" ]; then CMP=newer; else CMP="$(jq -nr --arg want "$WANT" --arg have "$INSTALLED" "$VKEY"' if ($want|vkey) > ($have|vkey) then "newer" elif ($want|vkey) == ($have|vkey) then "same" else "older" end')"; fi
[ -n "$CMP" ] || { log "cannot compare versions '$WANT' and '$INSTALLED'; not installing"; exit 0; }
if [ "$CMP" = older ] || { [ "$CMP" = same ] && [ "$OURS" = 1 ]; }; then
    log "nothing to install: newest release $WANT, installed $INSTALLED ($([ "$OURS" = 1 ] && echo ours || echo "not ours"))"
    exit 0
fi
# A release that failed its stay-alive check is not installed again until someone passes --retry.
REFUSED="$HOME/Library/Application Support/notchcast/refused-release"
if [ "$RETRY" = 0 ] && [ "$(cat "$REFUSED" 2>/dev/null)" = "$WANT" ]; then
    log "$WANT did not stay alive at its last install; run update.sh --retry to try it again"
    exit 0
fi
log "preparing $TAG over ${INSTALLED:-nothing} ($([ "$OURS" = 1 ] && echo ours || echo "not ours"))"
[ "$DRY" = 1 ] && exit 0

read_idle() {
    IDLE="$(if [ -n "${NOTCHCAST_IDLE_COMMAND:-}" ]; then
        "$NOTCHCAST_IDLE_COMMAND"
    else
        ioreg -c IOHIDSystem | awk '/"HIDIdleTime"/ {printf "%.0f\n", int($NF / 1000000000); exit}'
    fi)" || IDLE=0
    case "$IDLE" in ''|*[!0-9]*) IDLE=0 ;; esac
}

if [ -d "$APP" ]; then
    POLLS=0
    while true; do
        read_idle
        if [ "$IDLE" -ge 300 ]; then
            log "installing $TAG (idle $IDLE s)"
            break
        fi
        if [ "$POLLS" -ge "${NOTCHCAST_IDLE_POLL_LIMIT:-50}" ]; then
            log "Mac in use; installing at the next run"
            exit 0
        fi
        [ "$POLLS" != 0 ] || log "waiting for Mac to be idle (idle $IDLE s)"
        sleep "${NOTCHCAST_IDLE_POLL_SECONDS:-30}"
        POLLS=$((POLLS + 1))
    done
fi

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

if [ -d "$APP" ]; then
    read_idle
    if [ "$IDLE" -lt 300 ]; then
        log "Mac in use; installing at the next run"
        exit 0
    fi
fi

STATUS=0
"$HERE/install-app.sh" "$NEW" || STATUS=$?
if [ "$STATUS" = 75 ]; then log "another install is running; nothing changed"; exit 0; fi
if [ "$STATUS" != 0 ]; then
    mkdir -p "$(dirname "$REFUSED")"
    echo "$WANT" > "$REFUSED"
    exit 1
fi
rm -f "$REFUSED"
