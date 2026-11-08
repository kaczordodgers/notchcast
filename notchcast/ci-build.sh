#!/bin/bash
set -euo pipefail
TOOLS=$(cd "$(dirname "$0")/.." && pwd)
step() {
    echo "$1" > "$RUNNER_TEMP/step"
    echo "::group::$1"
}
step xcode
source "$TOOLS/notchcast/ci-xcode.sh"
# The fork-strings check compares against upstream's catalog, so fetch upstream first.
step upstream
git fetch -q --no-tags https://github.com/abue-ammar/tinycast.git "+refs/heads/main:refs/remotes/upstream/main"
export UPSTREAM=$(git merge-base HEAD refs/remotes/upstream/main)
step xcstrings
if [ -n "${BASE_SHA:-}" ]; then
    python3 notchcast/test-xcstrings.py
    python3 notchcast/check-xcstrings-order.py --base-ref "$BASE_SHA" --head "$HEAD_SHA"
fi
step xcodegen
source "$TOOLS/notchcast/ci-xcodegen.sh"
"$XCODEGEN" generate --quiet
step bundle-readme
bash notchcast/check-bundle-readme.sh
if [ -n "${BASE_SHA:-}" ]; then
    python3 notchcast/check-module-harness.py "$BASE_SHA" "$HEAD_SHA" || true
fi
step feature-shape
python3 notchcast/check-feature-shape.py
python3 notchcast/check-backup-schema.py
step legacy-ids
python3 notchcast/check-legacy-command-ids.py
step script-tests
python3 notchcast/script-tests.py
step build
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
    -jobs "${CHAD_BUILD_QUEUE_JOBS:-4}" -derivedDataPath "$RUNNER_TEMP/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build -quiet
step identity
source "$TOOLS/notchcast/config.env"
bash "$TOOLS/notchcast/check-identity.sh" app "$RUNNER_TEMP/DerivedData/Build/Products/Debug/$APP_NAME Dev.app"
step lint
command -v swiftlint >/dev/null || brew install --quiet swiftlint
./Scripts/lint.sh
step harnesses
bash "$TOOLS/notchcast/ci-tests.sh"
step complete
