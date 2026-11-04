#!/bin/bash
set -euo pipefail
VERSION=2.46.0
SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
curl -sSfLo "$RUNNER_TEMP/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/${VERSION}/xcodegen.zip"
echo "$SHA256  $RUNNER_TEMP/xcodegen.zip" | shasum -a 256 -c -
unzip -q -o "$RUNNER_TEMP/xcodegen.zip" -d "$RUNNER_TEMP/xcodegen"
export XCODEGEN="$RUNNER_TEMP/xcodegen/xcodegen/bin/xcodegen"
if [ -n "${GITHUB_ENV:-}" ]; then echo "XCODEGEN=$XCODEGEN" >> "$GITHUB_ENV"; fi
