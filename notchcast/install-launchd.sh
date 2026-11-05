#!/bin/bash
# Install Notchcast for this user. Usage: install-launchd.sh all|update|app|kick [--auto-install]
#   all     first install: update.sh installs /Applications/Notchcast.app, migrate.sh copies the old Tinycast data once,
#           the old Tinycast .app goes to the Trash (its data stays), then both agents below are loaded.
#   update  notchcast.update runs notchcast/update.sh every 30 min (needs gh logged in).
#   kick    notchcast.kick runs notchcast/kick.sh every 10 min: starts the sync when upstream moved (needs gh).
#   app     notchcast.app runs the app itself: started at login, restarted 10 s after a crash or a Quit.
#           Stop:  launchctl bootout gui/$(id -u)/notchcast.app
#           Start: launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/notchcast.app.plist
# Builds and releases run on GitHub Actions (.github/workflows/sync.yml), not on a Mac.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
APP="/Applications/$APP_NAME.app"
LOGS="$HOME/Library/Logs/notchcast"
DOMAIN="gui/$(id -u)"
UPDATE_ARG=""
case "${2:-}" in
    --auto-install) UPDATE_ARG=--install ;;
    "") ;;
    *) echo "usage: $0 all|update|app|kick [--auto-install]" >&2; exit 2 ;;
esac
[ "$#" -le 2 ] || { echo "too many arguments" >&2; exit 2; }
mkdir -p "$LOGS" "$HOME/Library/LaunchAgents"

agent() { # label log-name extra-plist-keys program...
    local label=$1 name=$2 extra=$3; shift 3
    local plist="$HOME/Library/LaunchAgents/$label.plist" args=""
    for a in "$@"; do args="$args<string>$a</string>"; done
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array>$args</array>
<key>RunAtLoad</key><true/>
$extra
<key>StandardOutPath</key><string>$LOGS/$name.log</string>
<key>StandardErrorPath</key><string>$LOGS/$name.log</string>
</dict></plist>
PLIST
    plutil -lint -s "$plist"
    launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$plist"
    echo "loaded $label -> $LOGS/$name.log"
}

# Login Items shows the executable, so a job runs through a named wrapper rather than /bin/bash.
named_job() { # name program...
    local name=$1
    local wrapper="$HOME/Library/Application Support/notchcast/jobs/$1"; shift
    mkdir -p "$(dirname "$wrapper")"
    printf '#!/bin/bash\n' > "$wrapper"
    if [ "$name" = 'Notchcast update' ]; then
        printf 'repo=%q\n' "$HERE/.." >> "$wrapper"
        cat >> "$wrapper" <<'REFRESH'
set -o pipefail
root="$HOME/Library/Application Support/notchcast"
tools="$root/tools"
stage=''
refresh() {
    git -C "$repo" fetch --quiet origin main 2>/dev/null || return 1
    stage=$(mktemp -d "$root/tools.XXXXXX") || return 1
    git -C "$repo" archive refs/remotes/origin/main notchcast/ 2>/dev/null | tar -xf - -C "$stage" 2>/dev/null || return 1
    [ -f "$stage/notchcast/update.sh" ] && [ -f "$stage/notchcast/install-app.sh" ] \
        && [ -f "$stage/notchcast/config.env" ] || return 1
    local old
    old=$(readlink "$tools")
    ln -s "$stage/notchcast" "$stage/link" && mv -fh "$stage/link" "$tools" || return 1
    stage=''
    case "$old" in "$root"/tools.??????/notchcast) rm -rf "${old%/notchcast}" ;; esac
}
if ! refresh; then
    echo 'tooling refresh failed; using previous code'
    [ -z "$stage" ] || rm -rf "$stage"
fi
REFRESH
        shift 2
        local args=''
        if [ "$#" -gt 0 ]; then args="$(printf '%q ' "$@")"; fi
        printf 'if [ -f "$tools/update.sh" ]; then exec /bin/bash "$tools/update.sh" %s; fi\n' \
            "$args" >> "$wrapper"
        set -- /bin/bash "$HERE/update.sh" "$@"
    fi
    printf 'exec %s\n' "$(printf '%q ' "$@")" >> "$wrapper"
    chmod 755 "$wrapper"
    /bin/bash -n "$wrapper"
    echo "$wrapper"
}

install_update() {
    agent notchcast.update update \
        '<key>StartInterval</key><integer>1800</integer>
<key>ProcessType</key><string>Background</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>' \
        "$(named_job 'Notchcast update' /bin/bash "$HERE/update.sh" ${UPDATE_ARG:+"$UPDATE_ARG"})"
}

install_kick() {
    agent notchcast.kick kick \
        '<key>StartInterval</key><integer>600</integer>
<key>ProcessType</key><string>Background</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>' \
        "$(named_job 'Notchcast sync check' /bin/bash "$HERE/kick.sh")"
}

install_app() {
    local exe
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "$BUNDLE_ID" ] \
        || { echo "$APP is not $BUNDLE_ID" >&2; exit 1; }
    exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
    # One instance only: a copy started by Finder quits before the agent starts its own.
    if pgrep -f "^$APP/Contents/MacOS/$exe( |$)" >/dev/null && ! launchctl print "$DOMAIN/notchcast.app" >/dev/null 2>&1; then
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        for _ in $(seq 1 20); do pgrep -f "^$APP/Contents/MacOS/$exe( |$)" >/dev/null || break; sleep 0.5; done
    fi
    # NOTCHCAST_LAUNCHD=1 makes the app keep its own login item off (commit "Notchcast: let a LaunchAgent own starting the app").
    agent notchcast.app app \
        '<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>ProcessType</key><string>Interactive</string>
<key>LimitLoadToSessionType</key><string>Aqua</string>
<key>EnvironmentVariables</key><dict><key>NOTCHCAST_LAUNCHD</key><string>1</string></dict>' \
        "$APP/Contents/MacOS/$exe"
}

first_install() {
    /bin/bash "$HERE/update.sh" ${UPDATE_ARG:+"$UPDATE_ARG"}
    [ -d "$APP" ] || { echo "no $APP after update.sh; see its output" >&2; exit 1; }
    /bin/bash "$HERE/migrate.sh"
    # The old app goes to the Trash, never rm; its preferences, data and Keychain items stay where they are.
    if [ -d "$OLD_APP" ]; then
        local trashed
        trashed="$HOME/.Trash/$(basename "$OLD_APP" .app) $(date +%Y%m%d-%H%M%S).app"
        mv "$OLD_APP" "$trashed"
        echo "old app moved to $trashed"
    fi
}

case "${1:-}" in
    all) first_install; install_update; install_kick; install_app ;;
    update) install_update ;;
    kick) install_kick ;;
    app) install_app ;;
    *) echo "usage: $0 all|update|app|kick [--auto-install]" >&2; exit 2 ;;
esac
