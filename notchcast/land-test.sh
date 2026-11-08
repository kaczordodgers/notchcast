#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
sync_wait_tests() (
    set -euo pipefail
    source "$root/notchcast/sync-wait.sh"
    declare -f wait_for_sync >/dev/null || { echo 'FAIL: Sync wait helper missing'; exit 1; }
    refuse() { echo "REFUSED: $*"; exit 1; }
    export NOTCHCAST_TEST_SYNC_POLL_SECONDS=1 NOTCHCAST_TEST_SYNC_LIMIT_SECONDS=2
    sleeps=0
    sleep() { sleeps=$((sleeps + 1)); SECONDS=$((SECONDS + $1)); }
    gh() {
        if [ "$2" = list ]; then
            [[ "$*" == *'--workflow sync.yml'* ]] || exit 1
            [[ "$*" == *'--status queued'* || "$*" == *'--status in_progress'* ]] || exit 1
            [ "$scenario" != none ] && echo 123
            return 0
        fi
        [[ "$*" == *'--json jobs --jq '* ]] || exit 1
        [ "$scenario" != broken ] || return 1
        case "$scenario" in
            main) echo '{"jobs":[{"name":"main","status":"in_progress"}]}' ;;
            gone) if [ "$sleeps" -eq 0 ]; then echo '{"jobs":[{"name":"replay","status":"in_progress"}]}'; else echo '{"jobs":[]}'; fi ;;
            queued) echo '{"jobs":[{"name":"replay","status":"queued"}]}' ;;
            plan-queued) echo '{"jobs":[{"name":"plan","status":"queued"}]}' ;;
            planning) if [ "$sleeps" -eq 0 ]; then echo '{"jobs":[{"name":"plan","status":"in_progress"}]}'
                else echo '{"jobs":[{"name":"plan","status":"completed","conclusion":"success"},{"name":"main","status":"in_progress"}]}'; fi ;;
            planned) if [ "$sleeps" -eq 0 ]; then echo '{"jobs":[{"name":"plan","status":"completed","conclusion":"success"}]}'
                else echo '{"jobs":[{"name":"plan","status":"completed","conclusion":"success"},{"name":"replay","status":"completed"}]}'; fi ;;
            *) echo '{"jobs":[{"name":"replay","status":"in_progress"}]}' ;;
        esac | jq "${@: -1}"
    }
    for scenario in none main gone plan-queued planning planned; do
        sleeps=0
        wait_for_sync
        case "$scenario" in gone|planning|planned) [ "$sleeps" -eq 1 ] ;; *) [ "$sleeps" -eq 0 ] ;; esac
        echo "PASS: Sync $scenario"
    done
    for scenario in forever queued; do
        sleeps=0
        output=$(wait_for_sync) && exit 1
        [[ "$output" == *'REFUSED: Sync run 123 (plan or replay) still running after 40 min; try again'* ]]
        echo "PASS: Sync $scenario refuses at limit"
    done
    scenario=broken
    output=$(wait_for_sync) && exit 1
    [[ "$output" == *'REFUSED: could not read Sync run 123'* ]]
    echo 'PASS: Sync unreadable run refuses'
)
pr=42
sync_wait_tests
if [ "${1:-}" = --sync ]; then exit 0; fi
mkdir -p "${NOTCHCAST_SCRATCH:=$HOME/Library/Caches/notchcast}"
scratch=$(mktemp -d "$NOTCHCAST_SCRATCH/land-test.XXXXXX")
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
(
    eval "$(sed -n '/^delete_head() {$/,/^}$/p' "$root/notchcast/land.sh")"
    git init --quiet --bare "$scratch/remote.git"
    git clone --quiet "$scratch/remote.git" "$scratch/delete"
    cd "$scratch/delete"
    git -c user.name=Fixture -c user.email=fixture@example.com commit --quiet --allow-empty -m base
    head=$(git rev-parse HEAD)
    git branch matching
    git push --quiet origin matching
    delete_head matching "$head"
    [ -z "$(git ls-remote origin refs/heads/matching)" ]
    ! git show-ref --verify --quiet refs/heads/matching
    git -c user.name=Fixture -c user.email=fixture@example.com commit --quiet --allow-empty -m moved
    moved=$(git rev-parse HEAD)
    git branch remote-moved
    git push --quiet origin remote-moved
    delete_head remote-moved "$head"
    [ "$(git ls-remote origin refs/heads/remote-moved | cut -f1)" = "$moved" ]
    git branch local-moved
    git push --quiet origin "$head:refs/heads/local-moved"
    delete_head local-moved "$head"
    [ "$(git rev-parse local-moved)" = "$moved" ]
    delete_head remote-moved "$moved" true
    [ -n "$(git ls-remote origin refs/heads/remote-moved)" ]
    echo 'PASS: delete_head matching, moved remote, moved local and fork'
)
if [ "${1:-}" = --statuses ]; then
    echo 'PASS: local build status fixtures'
    exit 0
fi
git clone --quiet --no-hardlinks "$root" "$scratch/repo"
cd "$scratch/repo"
git config user.name Damian
git config user.email 336236323+kaczordodgers@users.noreply.github.com
printf '#!/usr/bin/env python3\n' > notchcast/check-drift.py
printf '#!/usr/bin/env python3\n' > notchcast/check-drift-test.py
git add notchcast/check-drift.py notchcast/check-drift-test.py
git commit --quiet -m 'Fixture: isolate drift gates covered by land-drift-test.py'
base=$(git rev-parse HEAD)
# A Sync rewrite: old main has our commit; new main is upstream's next commit plus the same change replayed.
fixture_commit() {
    printf '%s\n' "$2" > "notchcast/$1.fixture"
    git add "notchcast/$1.fixture"
    git commit --quiet -m "Fixture: $1 $2"
}
git switch --quiet -c fork-old "$base"
fixture_commit ours old
old=$(git rev-parse HEAD)
git switch --quiet -c fork-new "$base"
fixture_commit upstream new
fixture_commit ours old
new=$(git rev-parse HEAD)
git switch --quiet -c fork-clean "$old"
fixture_commit ours edited
clean=$(git rev-parse HEAD)
git switch --quiet -c fork-conflict "$old"
fixture_commit upstream pr
conflict=$(git rev-parse HEAD)
status=0
"$root/notchcast/land.sh" --check "$new" "$clean" > "$scratch/fork.log" 2>&1 || status=$?
[ "$status" -eq 1 ] && grep -q 'REFUSED: merge conflict: notchcast/ours.fixture' "$scratch/fork.log"
echo 'PASS: without a recorded tip, a PR from before the rewrite conflicts with its own replayed commit'
git update-ref "refs/notchcast/synced/$old" "$old"
git update-ref "refs/notchcast/synced/$new" "$new"
"$root/notchcast/land.sh" --check "$new" "$clean" > "$scratch/fork.log" 2>&1 || { cat "$scratch/fork.log"; exit 1; }
grep -q "merging from ${old:0:8}" "$scratch/fork.log"
echo 'PASS: a PR from before the rewrite lands from its recorded fork point, past a newer recorded tip'
status=0
"$root/notchcast/land.sh" --check "$new" "$conflict" > "$scratch/fork.log" 2>&1 || status=$?
[ "$status" -eq 1 ] && grep -q 'REFUSED: merge conflict: notchcast/upstream.fixture' "$scratch/fork.log"
echo 'PASS: a real conflict from the recorded fork point still refuses'
git switch --quiet -c fork-updated "$old"
git merge --quiet --no-edit "$new"
fixture_commit pr updated
updated=$(git rev-parse HEAD)
git switch --quiet -c fork-newer "$new"
fixture_commit upstream newer
"$root/notchcast/land.sh" --check HEAD "$updated" > "$scratch/fork.log" 2>&1 || { cat "$scratch/fork.log"; exit 1; }
if grep -q 'merging from' "$scratch/fork.log"; then cat "$scratch/fork.log"; exit 1; fi
echo 'PASS: a PR from before the rewrite that merged the new main lands by a plain merge'
git for-each-ref --format='delete %(refname)' refs/notchcast/synced/ | git update-ref --stdin
if [ "${1:-}" = --fork ]; then exit 0; fi
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
# Unwired, so harnesses that iterate every feature expect no search entry for it.
s, count = re.subn(r'(    static let unwired: Set<Self> = \[\n)', r'\g<1>        .landingFixture,\n', s)
assert count == 1, 'unwired'
p.write_text(s)
# NotchcastSettingsModule.module(of:) traps for a feature placed nowhere in the settings tree.
p = Path('Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettingsModule+Groups.swift')
line = '                .feature(.todoIsland, settings: []),\n'
s = p.read_text()
assert s.count(line) == 1, 'tree'
p.write_text(s.replace(line, line + '                .feature(.landingFixture, settings: []),\n'))
import json
p = Path('notchcast/switch-path-allowlist-2026-11-04.json')
paths = json.loads(p.read_text())
paths['landingFixture'] = 'Synthetic feature used only by the merged-tree landing test.'
p.write_text(json.dumps(paths, indent=2) + '\n')
# nc-SettingsBackup-engine-test requires every feature to be classified for backups.
p = Path('Tinycast/Features/SettingsBackup/Model/ForkSettingsBackupSchema.swift')
s = p.read_text().replace('    static let excluded: Set<String> = [\n',
                          '    static let excluded: Set<String> = [\n        "landingFixture",\n', 1)
assert '"landingFixture"' in s
p.write_text(s)
PY
git add Tinycast/Features/Notchcast/Core/NotchcastFeature.swift notchcast/switch-path-allowlist-2026-11-04.json \
    Tinycast/Features/SettingsBackup/Model/ForkSettingsBackupSchema.swift \
    Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettingsModule+Groups.swift
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
