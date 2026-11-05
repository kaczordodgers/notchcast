#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/sync-strings.sh
args=()
while IFS= read -r file; do args+=(--stringsdata "$file"); done < <(
    find build/strings/Build/Intermediates.noindex/Tinycast.build/Debug/Tinycast.build -name '*.stringsdata'
)
xcrun xcstringstool sync Tinycast/Resources/Notchcast.xcstrings "${args[@]}"
python3 notchcast/check-fork-strings.py
