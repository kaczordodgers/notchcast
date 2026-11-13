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
    *check-runs*)
        sha=$*
        sha=${sha#*commits/}
        if grep -qxF "${sha%%/*}" "$FIXTURE/green" 2>/dev/null; then echo success; else echo "${HEAD_CHECKS:-success}"; fi ;;
    'workflow run '*)
        [[ -z "${DISPATCH_FAILS:-}" || "$*" != *"--ref $DISPATCH_FAILS "* ]] || { echo 'HTTP 422' >&2; exit 1; }
        echo "$*" >> "$FIXTURE/dispatched" ;;
    'run list '*databaseId,status*) ;;
    # A dispatched train run is red when its branch train/<a>-<b> names a PR in RED_PRS.
    'run list '*workflow_dispatch*)
        branch=$*
        branch=${branch#*-b train/}
        verdict=success
        for pr in ${RED_PRS:-}; do
            [[ "-${branch%% *}-" != *"-$pr-"* ]] || verdict=failure
        done
        echo "$verdict" ;;
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
cp "$root"/notchcast/{land.sh,train.sh,merge.sh,local-build-status.sh,drift-gates.sh,sync-wait.sh,hold.sh,config.env,fork-point.sh,land-tooling.txt,ci.py,app-proof.py,app-proofs.json} "$seed/notchcast/"
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
[ ! -e "$FIXTURE/slow" ] || { echo $$ > "$FIXTURE/started"; sleep 20; }
mkdir -p "$BIN"
ran=
status=0
run() {
    local name=$1
    case " $NOTCHCAST_ONLY_TESTS " in *" $name "*) ;; *) return 0 ;; esac
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
echo 'red-with: src/e.txt' > "$seed/Tests/clipboard-text-test.swift"
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
        '{state: "OPEN", isDraft: false, headRefOid: $head, headRefName: $branch, baseRefName: "main", isCrossRepository: false, title: $title, body: "", labels: []}' \
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

# train.sh <pr>...: prints "GREEN <branch> <sha8> on main <base8>: notchcast/land.sh --train-run <sha> <prs>".
train() {
    status=0
    NOTCHCAST_TRAIN_POLL=0 bash notchcast/train.sh "$@" > "$FIXTURE/train-output" 2>&1 || status=$?
    train_sha=$(sed -n 's/^GREEN .*--train-run \([0-9a-f]*\) .*/\1/p' "$FIXTURE/train-output" | tail -1)
}
draft() { jq '.isDraft = true' "$FIXTURE/pr-$1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$1.json"; }
label() { jq '.labels += [{name: "land"}]' "$FIXTURE/pr-$1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$1.json"; }
untouched() { [ "$(origin rev-parse main)" = "$base" ] && [ ! -e "$FIXTURE/closed" ] && [ ! -e "$FIXTURE/hold" ]; }

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
[ "$status" -eq 0 ] && [ -n "$train_sha" ] || { cat "$FIXTURE/train-output"; fail 'a green train did not report its run'; }
[ "$(origin rev-parse refs/heads/train/1-2)" = "$train_sha" ] && [ "$(origin rev-parse "$train_sha~2")" = "$base" ] \
    && [ "$(origin rev-parse "$train_sha^2")" = "$(jq -r .headRefOid "$FIXTURE/pr-2.json")" ] || fail 'train/1-2 is not main plus each head'
[ "$(grep -c -- '--ref train/1-2' "$FIXTURE/dispatched")" -eq 4 ] && [ "$(grep -c "base=$base" "$FIXTURE/dispatched")" -eq 3 ] \
    || fail "dispatched '$(paste -sd'|' "$FIXTURE/dispatched")'"
echo "$train_sha" > "$FIXTURE/green"
draft 1
draft 2
label 1
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q '^REFUSED: draft #2 has no land label' "$FIXTURE/output" && untouched \
    || fail 'a draft without the land label landed on a green train run'
echo 'PASS: a draft without the land label is refused even under a green train run'
land 1
[ "$status" -eq 1 ] && grep -q '^REFUSED: PR must be open and ready; a draft lands only on a green train run' "$FIXTURE/output" && untouched \
    || fail 'a labelled draft landed without a train run'
echo 'PASS: a labelled draft without --train-run is refused as before'
label 2
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 0 ] && grep -q "train: ${train_sha:0:8} is green on main" "$FIXTURE/output" || fail 'a green train run did not cover its PRs'
[ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] && [ "$(origin rev-parse 'main^{tree}')" = "$(origin rev-parse "$train_sha^{tree}")" ] \
    || fail "the train run landed '$(landed)'"
[ -z "$(origin for-each-ref refs/heads/train/)" ] || fail 'the landed train branch was not deleted'
echo 'PASS: a green train run lands its labelled draft PRs, red on their own heads, as the exact tree it tested, and deletes its branch'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2 3
[ "$status" -eq 1 ] && grep -q "does not merge #3's head" "$FIXTURE/output" && grep -q '^REFUSED: [a-z]* is failure on' "$FIXTURE/output" && untouched \
    || fail 'a train run missing a PR head was not refused by the heads own checks'
echo 'PASS: a train run missing a PR head covers nothing and the heads own red checks refuse'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
git switch --quiet pr-c
echo moved > src/c.txt
git commit --quiet -am 'Move C'
git push --quiet origin pr-c pr-c:refs/pull/2/head
jq --arg head "$(git rev-parse HEAD)" '.headRefOid = $head' "$FIXTURE/pr-2.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-2.json"
git switch --quiet main
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q "does not merge #2's head" "$FIXTURE/output" && grep -q '^REFUSED: [a-z]* is failure on' "$FIXTURE/output" && untouched \
    || fail 'a PR head moved after the train was not refused'
echo 'PASS: a PR head that moved after the train run is refused as without a train'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
echo moved > src/moved.txt
git add src/moved.txt
git commit --quiet -m 'Fixture: main moves'
git push --quiet origin main
base=$(git rev-parse HEAD)
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q 'not current main' "$FIXTURE/output" && grep -q '^REFUSED: [a-z]* is failure on' "$FIXTURE/output" && untouched \
    || fail 'a train run on a stale base was not refused'
echo 'PASS: a train run whose base is no longer main is refused as without a train'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q "${train_sha:0:8} has build failure" "$FIXTURE/output" && untouched || fail 'a red train run was not refused'
echo 'PASS: a red train run covers nothing and lands nothing'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
RED_PRS=2 train 1 2 3
[ "$status" -eq 1 ] && grep -q '^RED train/1-2-3: splitting into 1 2 | 3$' "$FIXTURE/train-output" \
    && grep -q '^RED train/1-2: splitting into 1 | 2$' "$FIXTURE/train-output" && grep -q '^RED #2 alone' "$FIXTURE/train-output" \
    && grep -q '^GREEN train/3 .* --train-run [0-9a-f]* 3$' "$FIXTURE/train-output" && grep -q '^GREEN train/1 .* --train-run [0-9a-f]* 1$' "$FIXTURE/train-output" \
    || { cat "$FIXTURE/train-output"; fail 'a red train did not bisect to its red PR'; }
[ "$(origin for-each-ref --format='%(refname:lstrip=2)' refs/heads/train/ | paste -sd' ' -)" = 'train/1 train/3' ] || fail 'red train branches were kept'
untouched || fail 'train.sh touched main'
echo 'PASS: a red train splits in halves onto new trains down to the red PR, keeps only green train branches and lands nothing'

fixture
open_pr 1 pr-one 'Add one' src/shared.txt
open_pr 2 pr-two 'Add two' src/shared.txt
train 1 2
[ "$status" -eq 1 ] && grep -q 'REFUSED: merge conflict: src/shared.txt' "$FIXTURE/train-output" || { cat "$FIXTURE/train-output"; fail 'a conflicting train was not refused'; }
[ -z "$(origin for-each-ref refs/heads/train/)" ] && [ ! -e "$FIXTURE/dispatched" ] && untouched || fail 'a refused train pushed or dispatched'
echo 'PASS: a train whose merge is refused pushes no branch and dispatches nothing'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
origin update-ref refs/heads/train/3 "$base"
RED_PRS=2 train 1 2 3
[ "$status" -eq 1 ] && grep -q '^REFUSED: origin already has train/3' "$FIXTURE/train-output" || { cat "$FIXTURE/train-output"; fail 'a taken split name was not refused'; }
[ "$(origin for-each-ref --format='%(refname:lstrip=2)' refs/heads/train/)" = train/3 ] && ! grep -q -- '--ref train/1-2 ' "$FIXTURE/dispatched" && untouched \
    || fail "a split refused on a taken name left '$(origin for-each-ref refs/heads/train/)'"
echo 'PASS: a split round whose branch name is taken refuses before pushing any half'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
RED_PRS=2 DISPATCH_FAILS=train/3 train 1 2 3
[ "$status" -eq 1 ] && grep -q 'scrapping train/1-2, which has no verdict' "$FIXTURE/train-output" \
    && grep -q 'scrapping train/3, which has no verdict' "$FIXTURE/train-output" || { cat "$FIXTURE/train-output"; fail 'a failed dispatch scrapped nothing'; }
[ -z "$(origin for-each-ref refs/heads/train/)" ] && untouched || fail "a failed dispatch left '$(origin for-each-ref refs/heads/train/)'"
echo 'PASS: a split round that stops after pushing deletes every half it pushed'

# clipboard-text-test, which the hosted runner skips, is red with src/e.txt; a-test with src/a.txt and src/b.txt.
fixture
open_pr 1 pr-a 'Add A' src/a.txt
open_pr 2 pr-b 'Add B' src/b.txt src/clipboard-text.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
land --train-run "$train_sha" 1 2
[ "$status" -eq 0 ] && grep -q "^harnesses: covered by train ${train_sha:0:8} (tree identical)" "$FIXTURE/output" \
    || fail 'a covered train did not report its harnesses as covered'
[ "$(paste -sd'|' "$PASSES")" = clipboard-text-test ] || fail "a covered train ran '$(paste -sd'|' "$PASSES")'"
[ "$(landed)" = 'Notchcast: Add A (#1)|Notchcast: Add B (#2)' ] || fail "a covered train landed '$(landed)'"
echo 'PASS: a covered train runs only the harnesses its hosted runner skips, not the ones the train run passed'

fixture
open_pr 1 pr-a 'Add A' src/a.txt
open_pr 2 pr-e 'Add E' src/clipboard-text.txt src/e.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q "^REFUSED: train ${train_sha:0:8}: #2 clipboard-text-test failed; nothing lands on that run" "$FIXTURE/output" && untouched \
    || fail 'a red runner-skipped harness on a train run dropped a PR and landed the rest'
[ -n "$(origin rev-parse --verify -q refs/heads/train/1-2)" ] || fail 'a refused train lost its branch'
echo 'PASS: a red pass on a train run bisects to its breaking PR and lands no part of the train'

# Last: a killed lander can leave children behind.
for signal in TERM HUP; do
    fixture
    open_pr 1 pr-b 'Add B' src/b.txt
    : > "$FIXTURE/slow"
    bash notchcast/land.sh 1 > "$FIXTURE/output" 2>&1 &
    lander=$!
    for _ in $(seq 600); do [ -s "$FIXTURE/started" ] && break; sleep 0.1; done
    [ -s "$FIXTURE/started" ] || fail "the $signal lander never reached its harnesses"
    [ -s "$FIXTURE/hold" ] || fail "no hold while the harnesses ran"
    kill -"$signal" "$lander"
    status=0
    wait "$lander" || status=$?
    [ "$status" -ne 0 ] && [ ! -e "$FIXTURE/hold" ] || fail "a $signal left the hold behind (exit $status)"
done
echo 'PASS: a lander killed by TERM or HUP during its harnesses releases its hold'
fixture
open_pr 1 pr-b 'Add B' src/b.txt
: > "$FIXTURE/slow"
bash notchcast/land.sh 1 > "$FIXTURE/output" 2>&1 &
lander=$!
for _ in $(seq 600); do [ -s "$FIXTURE/started" ] && break; sleep 0.1; done
[ -s "$FIXTURE/started" ] || fail 'the lander never reached its harnesses'
kill -KILL "$lander" "$(cat "$FIXTURE/started")"  # the harness too, or it writes into the next fixture
wait "$lander" || true
[ -s "$FIXTURE/hold" ] || fail 'a SIGKILL ran the EXIT trap'
rm "$FIXTURE/slow"
land 1
[ "$status" -eq 0 ] && [ "$(landed)" = 'Notchcast: Add B (#1)' ] && [ ! -e "$FIXTURE/hold" ] || fail 'the hold of a killed lander refused the next one'
echo 'PASS: the next lander on the Mac takes over the hold of one killed by SIGKILL'
