#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/notchcast" "$scratch/Scripts" "$scratch/tmp"
cp "$root/notchcast/ci-tests.sh" "$root/notchcast/config.env" "$scratch/notchcast/"
cat > "$scratch/Scripts/run-tests.sh" <<'STUB'
#!/bin/bash
printf '%s' "${CI_SKIP_TESTS:-}" > "$SKIPS"
STUB
chmod +x "$scratch/Scripts/run-tests.sh"
cd "$scratch"
export TMPDIR="$scratch/tmp" SKIPS="$scratch/skips" GITHUB_ACTIONS=true
for runner in local self-hosted github-hosted; do
    export RUNNER_ENVIRONMENT=$runner
    [ "$runner" != local ] || unset RUNNER_ENVIRONMENT
    CI_SKIP_TESTS=inherited bash notchcast/ci-tests.sh
    if [ "$runner" = github-hosted ]; then
        grep -qw nc-ScreenText-ocr-test "$SKIPS"
    else
        [ ! -s "$SKIPS" ] || { echo "FAIL: $runner skipped harnesses"; exit 1; }
    fi
done
echo 'PASS: CI wrapper preserves skips only on GitHub-hosted runners'
