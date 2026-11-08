#!/bin/bash
# Notchcast updater: install the newest snapshot at /Applications/Notchcast.app and have the
# notchcast.app LaunchAgent restart it. Runs from launchd (notchcast.update) and from install-launchd.sh (first install).
# It installs only a build with our bundle id (BUNDLE_ID), the release's version and our leaf certificate (SIGN_SHA1),
# and only when nothing is installed yet, the release is newer, or the installed copy is not ours.
# It replaces only the bundle, keeping one previous app for rollback; settings and data are never touched.
# The in-app updater stays inert for app.notchcast (ReleaseChannel: development), so this is the update path.
# --install installs even with automatic updates off, e.g. to put one build on every maintainer machine.
# Usage: update.sh [--install] [--retry] [--dry-run] (any order)
# A newer release installs and restarts the app at once, whether or not the Mac is in use.
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
# Only where ~/.config/notchcast/private.env defines notchcast_notify (notchcast/README.md, "Private hooks"), so one
# Mac acts: it is told once per issue and cause, and with notchcast_task each design issue becomes one private task
# and is closed.
if [ -f "$HOME/.config/notchcast/private.env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.config/notchcast/private.env"
fi
alert_issues() {
    declare -F notchcast_notify >/dev/null || return 0
    local seen="$HOME/Library/Application Support/notchcast/alerted-issues" issues key n
    mkdir -p "$(dirname "$seen")"; touch "$seen"
    issues="$(gh issue list -R "$FORK_REPO" --state open --limit 50 --json number,title,url,body,labels \
        --jq '.[] | select(any(.labels[]; .name == "notchcast-sync" or .name == "notchcast-main" or .name == "notchcast-release"))
              | [(.number|tostring) + ":" + ((.body | capture("<!-- cause: (?<c>.*) -->").c) // .title), .title, .url] | @tsv')"
    while IFS=$'\t' read -r key title url; do
        [ -n "$key" ] && ! grep -qxF "$key" "$seen" || continue
        if [ "$DRY" = 1 ]; then log "would alert: $title"; continue; fi
        printf 'Notchcast: %s. Nothing was pushed or published. %s\n' "$title" "$url" | notchcast_notify \
            || { log "notify for $title failed; retried next run"; return 1; }
        echo "$key" >> "$seen"
        log "notified: $title"
    done <<< "$issues"
    for n in $(gh issue list -R "$FORK_REPO" --state open --label notchcast-design --json number --jq '.[].number'); do
        if ! declare -F notchcast_task >/dev/null; then
            log "no notchcast_task hook; design issue #$n left open"
            continue
        fi
        if [ "$DRY" = 1 ]; then log "would add a task for design issue #$n"; continue; fi
        local body task
        body="$(gh issue view "$n" -R "$FORK_REPO" --json body,url --jq '.body + "\n" + .url')"
        task="$(notchcast_task "Refresh notchcast/docs/design-system.md" "$body")"
        [ -n "$task" ] || { log "task for design issue #$n not created; retried next run"; return 1; }
        # A failed close would make the next run add a second task.
        gh issue close "$n" -R "$FORK_REPO" --comment "Tracked privately." >/dev/null \
            || { log "design issue #$n: task $task created but the issue is still open; close it by hand"; return 1; }
        log "design issue #$n -> task $task"
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

SNAPSHOT='def snapshot: capture("[.]snapshot[.](?<stamp>[0-9]{14})$").stamp // "";'
TAG="$(gh release list -R "$FORK_REPO" -L 1000 --json tagName,isDraft \
    --jq "$SNAPSHOT [.[] | select(.isDraft | not) | select((.tagName | snapshot) != \"\")]
          | sort_by(.tagName | snapshot) | last | .tagName // empty")"
[ -n "$TAG" ] || { log "no $FORK_REPO snapshot yet"; exit 0; }
WANT="${TAG#v}"
CMP="$(jq -nr --arg want "$WANT" --arg have "$INSTALLED" "$SNAPSHOT"' if ($want|snapshot) > ($have|snapshot) then "newer" elif ($want|snapshot) == ($have|snapshot) then "same" else "older" end')"
if [ "$CMP" = older ] || { [ "$CMP" = same ] && [ "$OURS" = 1 ]; }; then
    log "nothing to install: newest snapshot $WANT, installed $INSTALLED ($([ "$OURS" = 1 ] && echo ours || echo "not ours"))"
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

STATUS=0
"$HERE/install-app.sh" "$NEW" || STATUS=$?
if [ "$STATUS" = 75 ]; then log "another install is running; nothing changed"; exit 0; fi
if [ "$STATUS" != 0 ]; then
    mkdir -p "$(dirname "$REFUSED")"
    echo "$WANT" > "$REFUSED"
    exit 1
fi
rm -f "$REFUSED"
