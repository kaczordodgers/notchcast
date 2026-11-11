#!/bin/bash
# Make this Mac a self-hosted Actions runner for FORK_REPO. Usage: install.sh <host> <count> [--gate '<command>']
#   <host> <count>  runners <host>-1 .. <host>-<count> in ~/agents/gh-runner/, each its own LaunchAgent
#                   notchcast.runner.<name> (KeepAlive), plus notchcast.runner-gate, which runs gate.sh every minute.
#   --gate          a shell command that must succeed for this Mac to take jobs; without it the Mac always does.
# Needs gh logged in as a repository admin. Run it again to change the count or the gate, never during a job.
# Remove a runner: launchctl bootout gui/$(id -u)/notchcast.runner.<name>, then ./config.sh remove in its folder.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../config.env"
VERSION=2.338.2
SHA256=25a065af409ffa317ab4d5a3b614dd15fc9c40f2172bc1b35a1b1258e919a388
usage() { echo "usage: $0 <host> <count> [--gate '<command>']" >&2; exit 2; }
[[ "${1:-}" =~ ^[a-z]+$ && "${2:-}" =~ ^[1-9]$ ]] || usage
HOST=$1 COUNT=$2 GATE=""
case "${3:-}" in
    --gate) GATE=${4:?}; [ "$#" -eq 4 ] || usage ;;
    "") ;;
    *) usage ;;
esac
ROOT="$HOME/agents/gh-runner"
LOGS="$HOME/Library/Logs/notchcast"
AGENTS="$HOME/Library/LaunchAgents"
DOMAIN="gui/$(id -u)"
ARCHIVE="$ROOT/actions-runner-osx-arm64-$VERSION.tar.gz"
mkdir -p "$ROOT" "$LOGS" "$AGENTS"

agent() { # template label name dir
    local plist="$AGENTS/$2.plist"
    sed -e "s|@NAME@|$3|g" -e "s|@DIR@|$4|g" -e "s|@ROOT@|$ROOT|g" -e "s|@LOGS@|$LOGS|g" \
        -e "s|@HOST@|$HOST|g" -e "s|@REPO@|$FORK_REPO|g" "$HERE/$1" > "$plist"
    plutil -lint -s "$plist"
    launchctl bootout "$DOMAIN/$2" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$plist"
    echo "loaded $2 -> $LOGS"
}

# The agents run these copies, so a checkout or worktree that goes away takes no runner with it.
cp "$HERE/gate.sh" "$HERE/job-started.sh" "$HERE/job-completed.sh" "$ROOT/"
chmod 755 "$ROOT/gate.sh" "$ROOT/job-started.sh" "$ROOT/job-completed.sh"
rm -f "$ROOT/admit"
if [ -n "$GATE" ]; then
    printf '#!/bin/bash\n%s\n' "$GATE" > "$ROOT/admit"
    chmod 755 "$ROOT/admit"
fi

for i in $(seq 1 "$COUNT"); do
    name="$HOST-$i"
    dir="$ROOT/$name"
    mkdir -p "$dir/tmp"
    if [ ! -f "$dir/.runner" ]; then
        if [ ! -f "$ARCHIVE" ]; then
            curl -sSfLo "$ARCHIVE" "https://github.com/actions/runner/releases/download/v$VERSION/$(basename "$ARCHIVE")"
        fi
        echo "$SHA256  $ARCHIVE" | shasum -a 256 -c - || { rm -f "$ARCHIVE"; exit 1; }
        tar -xzf "$ARCHIVE" -C "$dir"
        # The registration token lasts an hour and goes straight to config.sh: never printed, never stored.
        (cd "$dir" && ./config.sh --unattended --url "https://github.com/$FORK_REPO" --name "$name" \
            --labels notchcast-mac --work _work --replace \
            --token "$(gh api -X POST "repos/$FORK_REPO/actions/runners/registration-token" --jq .token)")
    fi
    agent runner.plist "notchcast.runner.$name" "$name" "$dir"
done
agent gate.plist notchcast.runner-gate "$HOST" "$ROOT"
