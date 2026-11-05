#!/bin/zsh
set -euo pipefail
here=${0:A:h}
python3 "$here/check-layout-test.py"
python3 "$here/inventory-test.py"
swift "$here/check-pixels-test.swift"
swift -D DEBUG "$here/offscreen-check.swift" --self-test
python3 "$here/keychain-test.py"
for source in "$here"/../../Tinycast/Features/Notchcast/Gallery/*.swift; do
  [[ $(head -1 "$source") =~ '^#if DEBUG( && [A-Z_]+)?$' && $(tail -1 "$source") == '#endif' ]] || { echo "FAIL Debug guard: $source"; exit 1; }
done
zsh -n "$here/snap.sh" "$here/offscreen-check.sh"
echo 'gallery harness: PASS'
