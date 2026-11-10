#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
# Debug's escaping-closure check embeds the absolute source path, and -file-prefix-map misses it.
build() {
    mkdir -p "$1/src" "$1/Fixture.app/Contents/MacOS"
    printf 'public func f(_ c: () -> Void) { withoutActuallyEscaping(c) { $0() } }\n' > "$1/src/C.swift"
    xcrun swiftc -swift-version 6 -Onone -module-name Fixture -emit-library "$1/src/C.swift" \
        -o "$1/Fixture.app/Contents/MacOS/Fixture.debug.dylib"
}
named="$scratch/$(printf '%s%s' private hq)/tree"
build "$named"
if python3 "$root/notchcast/check-identity.py" app "$named/Fixture.app" > "$scratch/output"; then
    echo 'FAIL: build path with the forbidden name accepted'
    exit 1
fi
grep -q '<forbidden-name>' "$scratch/output"
echo 'PASS: build path with the forbidden name refused'
build "$scratch/tree"
python3 "$root/notchcast/check-identity.py" app "$scratch/tree/Fixture.app"
echo 'PASS: the same build from a neutral path accepted'
