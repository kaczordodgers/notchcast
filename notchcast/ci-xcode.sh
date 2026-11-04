#!/bin/bash
set -euo pipefail
XCODE_PATH="$(find -E /Applications -maxdepth 1 -type d -regex '.*/Xcode_27(\.[0-9]+)*\.app' | sort -V | tail -n1)"
if [ -z "$XCODE_PATH" ]; then XCODE_PATH=/Applications/Xcode.app; fi
export DEVELOPER_DIR="$XCODE_PATH/Contents/Developer"
xcodebuild -version | head -n1 | grep -Eq '^Xcode 27(\.[0-9]+)*$' || {
    echo "::error::No released Xcode 27.x on this runner"; exit 1;
}
echo "Using $XCODE_PATH"
if [ -n "${GITHUB_ENV:-}" ]; then echo "DEVELOPER_DIR=$DEVELOPER_DIR" >> "$GITHUB_ENV"; fi
