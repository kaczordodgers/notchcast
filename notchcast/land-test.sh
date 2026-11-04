#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
mkdir -p "$HOME/agents/nc-local-ci"
scratch=$(mktemp -d "$HOME/agents/nc-local-ci/land-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
source "$root/notchcast/local-build-status.sh"
gh() { jq -s "${@: -1}" "$status_fixture"; }
status_fixture="$scratch/status"
printf '%s\n' '{"id":1,"context":"build/local","creator":{"login":"kaczordodgers"},"url":"https://api.github.com/repos/kaczordodgers/notchcast/statuses/head","state":"success"}' > "$status_fixture"
local_build_green head
echo 'PASS: local success accepted'
if local_build_green other; then exit 1; fi
echo 'PASS: different sha refused'
printf '%s\n' '{"id":2,"context":"build/local","creator":{"login":"kaczordodgers"},"url":"https://api.github.com/repos/kaczordodgers/notchcast/statuses/head","state":"failure"}' >> "$status_fixture"
if local_build_green head; then exit 1; fi
echo 'PASS: local failure refused'
printf '%s\n' '{"id":1,"context":"build/local","url":"https://api.github.com/repos/kaczordodgers/notchcast/statuses/head","state":"success","creator":{"login":"other"}}' > "$status_fixture"
if local_build_green head; then exit 1; fi
echo 'PASS: other creator refused'
rm "$status_fixture"
unset -f gh
if [ "${1:-}" = --statuses ]; then
    echo 'PASS: local build status fixtures'
    exit 0
fi
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
values = {'dependencies': '[]', 'settingsGroup': '.activities', 'title': '"Fixture"', 'subtitle': '"Fixture."',
          'requiredGrants': '[]'}
for name, value in values.items():
    s, count = re.subn(rf'(var {name}: [^\n]+ {{\n        switch self {{\n)',
                       rf'\g<1>        case .landingFixture: {value}\n', s)
    assert count == 1, name
s = s.replace('        return switch self {\n', '        return switch self {\n        case .landingFixture: false\n')
p.write_text(s)
import json
p = Path('notchcast/switch-paths.json')
paths = json.loads(p.read_text())
paths['landingFixture'] = 'Synthetic feature used only by the merged-tree landing test.'
p.write_text(json.dumps(paths, indent=2) + '\n')
PY
git add Tinycast/Features/Notchcast/Core/NotchcastFeature.swift notchcast/switch-paths.json
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
s = re.split(r'^    var ', Path('Tinycast/Features/Notchcast/Core/NotchcastFeature.swift').read_text(), flags=re.M)[0]
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
edit_config() {
    echo "$1" >> notchcast/config.env
    git add notchcast/config.env
    git commit --quiet -m "Fixture: $1"
}
git switch --quiet -c fixture-ours "$base"
edit_config '# ours'
ours=$(git rev-parse HEAD)
git switch --quiet -c fixture-conflict "$base"
edit_config '# theirs'
status=0
"$root/notchcast/land.sh" --check "$ours" HEAD > "$scratch/conflict.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep 'REFUSED: merge conflict' "$scratch/conflict.log"
git switch --quiet -c fixture-warning "$base"
python3 - <<'PY'
from pathlib import Path
import re
p = Path('Tinycast/Features/Notchcast/Core/NotchcastFeature.swift')
s, count = re.subn(r'(var defaultEnabled: Bool \{.*?\n        \}\n)', r'\g<1>        !isSystemFeature\n', p.read_text(), count=1, flags=re.S)
assert count == 1
p.write_text(s)
PY
git add Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
git commit --quiet -m 'Fixture: a second body after the first'
status=0
"$root/notchcast/land.sh" --check "$base" HEAD > "$scratch/warning.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep 'REFUSED: NotchcastFeature\*.swift does not typecheck without warnings' "$scratch/warning.log"
echo 'PASS: a warning in the feature files refuses the landing'
echo 'PASS: land-test.sh'
