#!/bin/bash
# land.sh <pr>... end to end on a fixture origin: real merges, squash chain and push; gh, swiftc and the checks are stubs.
set -euo pipefail
export LC_ALL=C
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
set -a
source "$root/notchcast/config.env"
set +a
seed="$scratch/seed"
mkdir -p "$scratch/bin" "$scratch/home" "$seed/notchcast" "$seed/Scripts" "$seed/Tests" "$seed/src" "$seed/Tinycast/Features/Notchcast/Core"
cat > "$scratch/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
    'pr view '*'--json headRefOid'*) jq -r .headRefOid "$FIXTURE/pr-$3.json" ;;
    'pr view '*) cat "$FIXTURE/pr-$3.json" ;;
    'pr close '*) echo "$3 ${*: -1}" >> "$FIXTURE/closed" ;;
    *check-runs*) echo success ;;
    *statuses*) ;;
    *actions/artifacts*) if [ -n "${TESTED:-}" ]; then echo '{"artifacts":[{"workflow_run":{"id":7}}]}'; else echo '{"artifacts":[]}'; fi ;;
    *actions/runs/7*) printf '{"name":"PR","path":".github/workflows/pr.yml","conclusion":"success","head_repository":{"full_name":"%s"},"html_url":"https://fixture.invalid/runs/7"}\n' "$FORK_REPO" ;;
    'variable get LANDING_HOLD'*) [ -s "$FIXTURE/hold" ] && cat "$FIXTURE/hold" || { echo 'variable LANDING_HOLD was not found' >&2; exit 1; } ;;
    'variable set LANDING_HOLD'*) echo "${*: -1}" > "$FIXTURE/hold" ;;
    'variable delete LANDING_HOLD'*) rm -f "$FIXTURE/hold" ;;
    'run list '*) ;;
    *) echo "gh stub: unexpected $*" >&2; exit 3 ;;
esac
STUB
printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/swiftc"
chmod +x "$scratch/bin/gh" "$scratch/bin/swiftc"
cp "$root"/notchcast/{land.sh,merge.sh,local-build-status.sh,drift-gates.sh,sync-wait.sh,hold.sh,config.env,fork-point.sh,land-tooling.txt,ci.py,app-proof.py,app-proofs.json} "$seed/notchcast/"
for name in check-feature-shape.py check-drift.py check-drift-test.py; do
    printf '#!/usr/bin/env python3\n' > "$seed/notchcast/$name"
done
printf '#!/bin/sh\n' > "$seed/notchcast/check-identity.sh"
printf '#!/bin/sh\n' > "$seed/notchcast/check-bundle-readme.sh"
# Selects core, and <name>-test for a changed src/<name>.txt, as changed-harnesses.sh does from harness inputs.
cat > "$seed/notchcast/changed-harnesses.sh" <<'STUB'
#!/bin/bash
echo notchcast-core-test
for path in $(git diff --name-only "$1" "$2" -- src); do
    name=$(basename "$path" .txt)-test
    [ ! -e "Tests/$name.swift" ] || echo "$name"
done
STUB
# One line per pass in $PASSES; a harness is red while every file its red-with line names exists.
cat > "$seed/Scripts/run-tests.sh" <<'STUB'
#!/bin/bash
BIN="$TMPDIR/tinycast-harness-fixture"
mkdir -p "$BIN"
ran=
status=0
run() {
    local name=$1
    local file red=1 needs
    needs=$(sed -n 's/^red-with: //p' "Tests/$name.swift")
    : > "$BIN/$name.log"
    ran="$ran${ran:+ }$name"
    [ -n "$needs" ] || red=0
    for file in $needs; do
        [ -e "$file" ] || red=0
    done
    [ "$red" -eq 0 ] || { : > "$BIN/$name.failed"; status=1; }
}
for file in Tests/*-test.swift; do
    run "$(basename "$file" .swift)"
done
echo "$ran" >> "$PASSES"
exit $status
STUB
chmod +x "$seed"/notchcast/*.sh "$seed/Scripts/run-tests.sh"
for name in notchcast-core b c clipboard-text; do
    echo '// fixture' > "$seed/Tests/$name-test.swift"
done
echo 'red-with: src/a.txt src/b.txt' > "$seed/Tests/a-test.swift"
echo 'red-with: src/d.txt' > "$seed/Tests/d-test.swift"
echo base > "$seed/src/shared.txt"
echo '# fixture' > "$seed/.gitattributes"
: > "$seed/Tinycast/Features/Notchcast/Core/NotchcastFeature.swift"
export HOME="$scratch/home" PATH="$scratch/bin:$PATH" NOTCHCAST_LAND_TOOLS=test
identify() { git config user.name "$MAINTAINER_NAME"; git config user.email "$MAINTAINER_EMAIL"; }
git init --quiet -b main "$seed"
cd "$seed"
identify
git add .
git commit --quiet -m 'Fixture seed'
# A fresh origin and checkout at the seed.
fixture() {
    cd "$scratch"
    rm -rf "$scratch/run"
    export FIXTURE="$scratch/run" PASSES="$scratch/run/passes"
    mkdir "$FIXTURE"
    git clone --quiet --bare "$seed" "$FIXTURE/origin.git"
    git clone --quiet "$FIXTURE/origin.git" "$FIXTURE/work"
    cd "$FIXTURE/work"
    identify
    git remote add upstream "$FIXTURE/origin.git"
    base=$(git rev-parse HEAD)
    : > "$PASSES"
}
# open_pr <number> <branch> <title> <path>...: a ready PR on origin whose head writes its title into each path.
open_pr() {
    local number=$1 branch=$2 title=$3 path
    shift 3
    git switch --quiet -c "$branch" "$base"
    for path in "$@"; do
        echo "$title" > "$path"
    done
    git add "$@"
    git commit --quiet -m "$title"
    git push --quiet origin "$branch" "$branch:refs/pull/$number/head"
    jq -n --arg head "$(git rev-parse HEAD)" --arg branch "$branch" --arg title "$title" \
        '{state: "OPEN", isDraft: false, headRefOid: $head, headRefName: $branch, baseRefName: "main", isCrossRepository: false, title: $title, body: ""}' \
        > "$FIXTURE/pr-$number.json"
    git switch --quiet main
}
selection() { notchcast/changed-harnesses.sh "$base" "$1"; }
land() {
    status=0
    bash notchcast/land.sh "$@" > "$FIXTURE/output" 2>&1 || status=$?
}
fail() { cat "$FIXTURE/output"; echo "FAIL: $1"; exit 1; }
origin() { git -C "$FIXTURE/origin.git" "$@"; }
landed() { origin log --reverse --format=%s "$base..main" | paste -sd'|' -; }
pass() { sed -n "$1p" "$PASSES"; }

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
union=$( { selection pr-b; selection pr-c; } | sort -u | paste -sd' ' -)
[ "$union" = 'b-test c-test notchcast-core-test' ] || fail "fixture union is '$union'"
land 1 2
[ "$status" -eq 0 ] || fail 'a green 2-PR train did not land'
[ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] || fail "train landed '$(landed)'"
[ -z "$(origin rev-list --merges "$base..main")" ] && [ "$(origin rev-parse main~2)" = "$base" ] || fail 'the chain is not one parent per PR from base'
[ "$(origin log --format='%an %ae %cn %ce' "$base..main" | sort -u)" = "$MAINTAINER_NAME $MAINTAINER_EMAIL $MAINTAINER_NAME $MAINTAINER_EMAIL" ] \
    || fail 'a squash is not the repo identity'
[ "$(origin ls-tree -r --name-only main -- src | paste -sd' ' -)" = 'src/b.txt src/c.txt src/shared.txt' ] || fail 'the landed tree lacks a PR'
[ "$(wc -l < "$PASSES")" -eq 1 ] && [ "$(pass 1)" = "$union" ] || fail "passes were '$(paste -sd'|' "$PASSES")', not one of '$union'"
grep -q "^1 Landed on main as $(origin rev-parse main~1) .* onto $base\.$" "$FIXTURE/closed" \
    && grep -q "^2 Landed on main as $(origin rev-parse main) .* onto $(origin rev-parse main~1)\.$" "$FIXTURE/closed" || fail 'close comments'
[ -z "$(origin for-each-ref refs/heads/pr-b refs/heads/pr-c)" ] || fail 'landed heads were not deleted'
[ ! -e "$FIXTURE/hold" ] || fail 'the train left its hold behind'
echo 'PASS: a 2-PR train lands one squash per PR after one harness pass over the union of their selections'

fixture
open_pr 1 pr-one 'Add one' src/shared.txt
open_pr 2 pr-two 'Add two' src/shared.txt
open_pr 3 pr-c 'Add C' src/c.txt
land 1 2 3
[ "$status" -eq 0 ] && grep -q 'REFUSED: merge conflict: src/shared.txt' "$FIXTURE/output" && grep -q 'DROPPED #2' "$FIXTURE/output" \
    || fail 'the conflicting PR was not dropped with its reason'
[ "$(landed)" = 'Notchcast: Add one (#1)|Notchcast: Add C (#3)' ] || fail "conflict train landed '$(landed)'"
[ "$(wc -l < "$PASSES")" -eq 1 ] && [ "$(pass 1)" = 'c-test notchcast-core-test' ] || fail "passes were '$(paste -sd'|' "$PASSES")'"
! grep -q '^2 ' "$FIXTURE/closed" && [ -n "$(origin rev-parse --verify -q refs/heads/pr-two)" ] || fail 'the dropped PR was closed or lost its head'
echo 'PASS: a PR that conflicts with the train is dropped and the rest lands'

# a-test is red only on a tree with both src/a.txt and src/b.txt: green on #1 alone, red from #2 on.
fixture
open_pr 1 pr-a 'Add A' src/a.txt
open_pr 2 pr-b 'Add B' src/b.txt
open_pr 3 pr-c 'Add C' src/c.txt
land 1 2 3
[ "$status" -eq 0 ] && grep -q 'DROPPED #2: a-test failed' "$FIXTURE/output" || fail 'a red train did not drop its breaking PR'
[ "$(landed)" = 'Notchcast: Add A (#1)|Notchcast: Add C (#3)' ] || fail "red train landed '$(landed)'"
[ "$(paste -sd'|' "$PASSES")" = 'a-test b-test c-test notchcast-core-test|a-test|a-test|a-test c-test notchcast-core-test' ] \
    || fail "full, bisect and final passes were '$(paste -sd'|' "$PASSES")'"
[ "$(origin ls-tree -r --name-only main -- src | paste -sd' ' -)" = 'src/a.txt src/c.txt src/shared.txt' ] || fail 'the landed tree is not #1 and #3'
! grep -q '^2 ' "$FIXTURE/closed" && [ "$(wc -l < "$FIXTURE/closed")" -eq 2 ] && [ -n "$(origin rev-parse --verify -q refs/heads/pr-b)" ] \
    || fail 'the breaking PR was closed or lost its head'
echo 'PASS: a red pass bisects on the failing harness, drops the breaking PR and lands the rest after their own green pass'

# The first push to main finds it moved to a commit made meanwhile: the chain is rebuilt on it and tested again.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
git switch --quiet -c meanwhile "$base"
echo moved > src/moved.txt
git add src/moved.txt
git commit --quiet -m 'Fixture: main moves'
git push --quiet origin meanwhile
git switch --quiet main
mkdir "$FIXTURE/bin"
cat > "$FIXTURE/bin/git" <<'STUB'
#!/bin/bash
if [ "$1" = push ] && [[ "$*" == *:refs/heads/main ]] && [ ! -e "$FIXTURE/moved" ]; then
    : > "$FIXTURE/moved"
    "$REAL_GIT" -C "$FIXTURE/origin.git" update-ref refs/heads/main refs/heads/meanwhile
fi
exec "$REAL_GIT" "$@"
STUB
chmod +x "$FIXTURE/bin/git"
REAL_GIT=$(command -v git) PATH="$FIXTURE/bin:$PATH" land 1 2
[ "$status" -eq 0 ] && grep -q 'merging again and rerunning harnesses' "$FIXTURE/output" || fail 'a train did not follow main'
[ "$(landed)" = 'Fixture: main moves|Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] || fail "after main moved the train landed '$(landed)'"
[ "$(paste -sd'|' "$PASSES")" = 'b-test c-test notchcast-core-test|b-test c-test notchcast-core-test' ] || fail "passes were '$(paste -sd'|' "$PASSES")'"
grep -q "^1 .* onto $(origin rev-parse meanwhile)\.$" "$FIXTURE/closed" || fail 'the close comment names the old base'
echo 'PASS: main moving under a train rebuilds the chain on it and reruns the pass'

fixture
open_pr 1 pr-d 'Add D' src/d.txt
land 1
[ "$status" -eq 1 ] && grep -q '^REFUSED: d-test failed$' "$FIXTURE/output" && ! grep -q DROPPED "$FIXTURE/output" || fail 'a red single PR'
[ "$(origin rev-parse main)" = "$base" ] && [ ! -e "$FIXTURE/closed" ] && [ ! -e "$FIXTURE/hold" ] || fail 'a refused PR left something behind'
echo 'PASS: a single red PR refuses as before and lands nothing'

# notchcast-core-test is red on main itself, so every PR's tree inherits it.
fixture
echo 'red-with: src/shared.txt' > Tests/notchcast-core-test.swift
git commit --quiet -am 'Fixture: main is red'
git push --quiet origin main
base=$(git rev-parse HEAD)
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
land 1 2 3
[ "$status" -eq 1 ] && [ "$(grep -c REFUSED "$FIXTURE/output")" -eq 1 ] && grep -q '^REFUSED: main is red: notchcast-core-test$' "$FIXTURE/output" \
    && ! grep -q DROPPED "$FIXTURE/output" || fail 'a red main did not refuse once without dropping a PR'
[ "$(origin rev-parse main)" = "$base" ] && [ ! -e "$FIXTURE/closed" ] && [ ! -e "$FIXTURE/hold" ] || fail 'a red main left something behind'
echo 'PASS: a harness red on main refuses the train once and drops nobody'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
for args in '1 2 1' '1 1'; do
    land $args
    [ "$status" -eq 1 ] && grep -q '^REFUSED: PR named more than once: 1$' "$FIXTURE/output" || fail "land.sh $args was not refused"
    [ "$(origin rev-parse main)" = "$base" ] && [ ! -e "$FIXTURE/closed" ] && [ ! -s "$PASSES" ] || fail "land.sh $args did something"
done
echo 'PASS: a PR named twice refuses the train before anything runs'

fixture
open_pr 1 pr-b 'Add B' src/b.txt src/clipboard-text.txt
TESTED=1 land 1
[ "$status" -eq 0 ] && grep -q 'https://fixture.invalid/runs/7 built and tested this tree' "$FIXTURE/output" || fail 'tested tree not reused'
[ "$(paste -sd'|' "$PASSES")" = clipboard-text-test ] || fail "with a tested tree the passes were '$(paste -sd'|' "$PASSES")'"
[ "$(landed)" = 'Notchcast: Add B (#1)' ] || fail "tested tree landed '$(landed)'"
echo 'PASS: a green PR build of the merged tree leaves only the harnesses its runner skips'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
held="2 $(($(date +%s) + 600))"
echo "$held" > "$FIXTURE/hold"
land 1 2
[ "$status" -eq 0 ] && grep -q 'landing is held for #2' "$FIXTURE/output" && [ "$(landed)" = 'Notchcast: Add C (#2)' ] \
    && [ "$(cat "$FIXTURE/hold")" = "$held" ] || fail "under a hold for #2 the train landed '$(landed)'"
echo 'PASS: under a hold for one of its PRs the train lands only that PR and leaves the hold'
