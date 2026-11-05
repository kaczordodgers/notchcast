#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
git init -q
git config user.name Damian
git config user.email 336236323+kaczordodgers@users.noreply.github.com
git commit -q --allow-empty -m 'Fixture base'
base=$(git rev-parse HEAD)
printf '%s%s\n' private hq > fixture.txt
git add fixture.txt
git commit -q -m 'Fixture addition'
git rm -q fixture.txt
git commit -q -m 'Fixture removal'
if python3 "$root/notchcast/check-identity.py" history "$base" > "$scratch/output"; then
    echo 'FAIL: intermediate forbidden addition accepted'
    exit 1
fi
grep -q '<forbidden-name>' "$scratch/output"
echo 'PASS: intermediate forbidden addition refused'
git switch -q --detach "$base"
mkdir notchcast
printf '%s%s\n' private hq > notchcast/check-identity.py
git add .
git commit -q -m 'Fixture allow list'
python3 "$root/notchcast/check-identity.py" history "$base"
echo 'PASS: allow-listed path accepted'
