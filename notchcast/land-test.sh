#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
mkdir -p "$HOME/agents/nc-ci-guard/land-test"
scratch=$(mktemp -d "$HOME/agents/nc-ci-guard/land-test/run.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
git clone --quiet --no-hardlinks "$root" "$scratch/repo"
cd "$scratch/repo"
git config user.name Damian
git config user.email 336236323+kaczordodgers@users.noreply.github.com
base=$(git rev-parse HEAD)
git switch --quiet -c fixture-a
python3 - <<'PY'
from pathlib import Path
p = Path('Tinycast/Features/Notchcast/Core/NotchcastFeature.swift')
s = p.read_text().replace('    case island,', '    case landingFixture\n    case island,', 1)
values = iter(['.system', '"Fixture"', '"Fixture."', '[]'])
s = s.replace('switch self {', 'switch self {\n        case .landingFixture: PLACEHOLDER')
for value in values:
    s = s.replace('PLACEHOLDER', value, 1)
assert 'PLACEHOLDER' not in s
p.write_text(s)
PY
git add Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
git commit --quiet -m 'Fixture: add enum case'
a=$(git rev-parse HEAD)
"$root/notchcast/changed-harnesses.sh" "$base" "$a" > "$scratch/selected"
grep -x notchcast-core-test "$scratch/selected"
grep -x nc-Battery-store-test "$scratch/selected"
"$root/notchcast/land.sh" --check "$base" "$a" > "$scratch/a.log" 2>&1 || { cat "$scratch/a.log"; exit 1; }
echo 'PASS: A alone'
git switch --quiet -c fixture-b "$base"
python3 - <<'PY'
from pathlib import Path
import re
s = Path('Tinycast/Features/Notchcast/Core/NotchcastFeature.swift').read_text().split('    enum SettingsGroup:')[0]
cases = [name.strip() for line in s.splitlines() if line.strip().startswith('case ')
         for name in line.strip().removeprefix('case ').split(',')]
p = Path('Tinycast/Features/Notchcast/Core/LandingFixture.swift')
p.write_text('func landingFixture(_ feature: NotchcastFeature) -> Bool {\n    switch feature {\n' +
             ''.join(f'    case .{name}: true\n' for name in cases) + '    }\n}\n')
p = Path('Tests/notchcast-core-test.swift')
p.write_text('// notchcast-sources: Tinycast/Features/Notchcast/Core/LandingFixture.swift\n' + p.read_text())
PY
git add Tinycast/Features/Notchcast/Core/LandingFixture.swift Tests/notchcast-core-test.swift
git commit --quiet -m 'Fixture: add exhaustive consumer'
b=$(git rev-parse HEAD)
"$root/notchcast/land.sh" --check "$base" "$b" > "$scratch/b.log" 2>&1 || { cat "$scratch/b.log"; exit 1; }
echo 'PASS: B alone'
git merge --quiet --no-commit --no-ff "$a"
git merge --abort
echo 'PASS: A and B merge without text conflicts'
status=0
"$root/notchcast/land.sh" --check "$b" "$a" > "$scratch/combined.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep 'REFUSED: notchcast-core-test failed' "$scratch/combined.log"
git switch --quiet -c fixture-conflict "$base"
python3 - <<'PY'
from pathlib import Path
p = Path('Tinycast/Features/Notchcast/Core/NotchcastFeature.swift')
p.write_text(p.read_text().replace('    case island,', '    case conflictingFixture,', 1))
PY
git add Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
git commit --quiet -m 'Fixture: conflicting edit'
status=0
"$root/notchcast/land.sh" --check "$a" HEAD > "$scratch/conflict.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep 'REFUSED: merge conflict' "$scratch/conflict.log"
echo 'PASS: land-test.sh'
