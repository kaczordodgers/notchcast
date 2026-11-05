#!/bin/bash
set -euo pipefail
plain=$(git merge-base "$1" "$2")
for tip in $(git for-each-ref --sort=-committerdate --format='%(objectname)' refs/notchcast/synced/); do
    git merge-base --is-ancestor "$plain" "$tip" || continue
    shared=$(git merge-base "$tip" "$2") || continue
    git merge-base --is-ancestor "$shared" "$1" || { echo "$shared"; exit; }
done
echo "$plain"
