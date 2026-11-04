#!/bin/bash
# Xcode copies every README.md under Tinycast/ into the app's Resources; a second one fails the build with
# "Multiple commands produce .../Resources/README.md". Checks the index of the current checkout.
set -euo pipefail
readmes=$(git ls-files 'Tinycast/*' | grep -E '(^|/)README\.md$' || true)
[ "$(printf '%s' "$readmes" | grep -c .)" -le 1 ] || { echo "More than one README.md under Tinycast/:" $readmes >&2; exit 1; }
