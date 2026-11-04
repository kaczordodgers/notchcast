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
import re
p = Path('Tinycast/Features/Notchcast/Core/NotchcastFeature.swift')
s = p.read_text().replace('    case island\n', '    case landingFixture\n    case island\n', 1)
values = {'settingsGroup': '.activities', 'title': '"Fixture"', 'subtitle': '"Fixture."',
          'requiredGrants': '[]', 'needsIslandArm': 'false'}
for name, value in values.items():
    s, count = re.subn(rf'(var {name}: [^\n]+ {{\n        switch self {{\n)',
                       rf'\g<1>        case .landingFixture: {value}\n', s)
    assert count == 1, name
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
s = Path('Tinycast/Features/Notchcast/Core/NotchcastFeature.swift').read_text().split('    var settingsGroup:')[0]
cases = re.findall(r'^    case (\w+)$', s, re.M)
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
logic=Tinycast/Features/Notchcast/Core/NotchcastFeature+Logic.swift
edit_default() {
    python3 - "$logic" "$1" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
assert '!isSystemFeature && self != .buildStats' in s
p.write_text(s.replace('!isSystemFeature && self != .buildStats', f'!isSystemFeature && self != .{sys.argv[2]} && self != .buildStats', 1))
PY
    git add "$logic"
    git commit --quiet -m "Fixture: default edit $1"
}
git switch --quiet -c fixture-ours "$base"
edit_default island
ours=$(git rev-parse HEAD)
git switch --quiet -c fixture-conflict "$base"
edit_default systemMonitor
status=0
"$root/notchcast/land.sh" --check "$ours" HEAD > "$scratch/conflict.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep 'REFUSED: merge conflict' "$scratch/conflict.log"
echo 'PASS: logic edits conflict instead of being appended'
git switch --quiet -c fixture-warning "$base"
printf 'extension NotchcastFeature {\n    var warningFixture: Bool {\n        let unused = 1\n        return true\n    }\n}\n' >> "$logic"
git add "$logic"
git commit --quiet -m 'Fixture: a warning'
status=0
"$root/notchcast/land.sh" --check "$base" HEAD > "$scratch/warning.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep 'REFUSED: NotchcastFeature\*.swift does not typecheck without warnings' "$scratch/warning.log"
echo 'PASS: a warning in the feature files refuses the landing'
echo 'PASS: land-test.sh'
