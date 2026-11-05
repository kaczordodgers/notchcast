#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
case "$1" in
    rev-parse) echo "$ROOT" ;;
    diff) printf '%s\0' "$CHANGED" ;;
esac
STUB
chmod +x "$scratch/bin/git"
export ROOT="$root" PATH="$scratch/bin:$PATH"
unset GITHUB_ACTIONS
for support in Command HotKey; do
    export CHANGED="Tests/Notchcast${support}HarnessSupport.swift"
    bash "$root/notchcast/changed-harnesses.sh" base head > "$scratch/selected"
    for name in app-installation-test launcher-settings-file-test hotkey-dispatch-test; do
        sources=$(name=$name bash -c 'source "$ROOT/notchcast/command-harness-sources.sh"; printf "%s\n" "$@"')
        if [[ "$sources" = *"$CHANGED"* ]]; then
            grep -qx "$name" "$scratch/selected" || { echo "FAIL: $CHANGED omitted $name"; exit 1; }
        fi
    done
done
echo 'PASS: shared command and hotkey support select all consumers'
