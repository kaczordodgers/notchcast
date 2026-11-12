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
unset GITHUB_ACTIONS RUNNER_ENVIRONMENT
for support in Command HotKey; do
    export CHANGED="Tests/Notchcast${support}HarnessSupport.swift"
    bash "$root/notchcast/changed-harnesses.sh" base head > "$scratch/selected"
    for name in AppInstallationTests LauncherSettingsFileTests HotKeyDispatchTests; do
        sources=$(name=$name bash -c 'source "$ROOT/notchcast/command-harness-sources.sh"; printf "%s\n" "$@"')
        if [[ "$sources" = *"$CHANGED"* ]]; then
            grep -qx "$name" "$scratch/selected" || { echo "FAIL: $CHANGED omitted $name"; exit 1; }
        fi
    done
    # An empty path once matched an empty pattern and selected every harness, upstream ones included.
    if grep -qx ExtensionTests "$scratch/selected"; then echo "FAIL: $CHANGED selected an unrelated upstream harness"; exit 1; fi
done
echo 'PASS: shared command and hotkey support select all consumers'
# A harness with no extra sources must not match every change (printf of no arguments prints one empty line).
export CHANGED="Tinycast/Features/Todo/TodoModule.swift"
bash "$root/notchcast/changed-harnesses.sh" base head > "$scratch/selected"
if grep -qx ExtensionTests "$scratch/selected"; then echo 'FAIL: an unrelated change selected ExtensionTests'; exit 1; fi
echo 'PASS: unrelated upstream harnesses stay unselected'
export CHANGED=Tests/nc-ScreenText-ocr-test.swift GITHUB_ACTIONS=true
for runner in local self-hosted github-hosted; do
    export RUNNER_ENVIRONMENT=$runner
    bash "$root/notchcast/changed-harnesses.sh" base head > "$scratch/selected"
    if [ "$runner" = github-hosted ]; then
        if grep -qx nc-ScreenText-ocr-test "$scratch/selected"; then echo 'FAIL: hosted runner selected OCR'; exit 1; fi
    else
        grep -qx nc-ScreenText-ocr-test "$scratch/selected" || { echo "FAIL: $runner omitted OCR"; exit 1; }
    fi
done
echo 'PASS: only GitHub-hosted runners omit VM-incompatible harnesses'
