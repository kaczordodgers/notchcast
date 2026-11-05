#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail
script=$(cd "$(dirname "$0")" && pwd)/main-harness-base.sh
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
git init -q
export GIT_AUTHOR_NAME=Test GIT_COMMITTER_NAME=Test
export GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_EMAIL=test@example.com
git commit -qm root --allow-empty
root=$(git rev-parse HEAD)
git commit -qm green --allow-empty
GREEN=$(git rev-parse HEAD)
git checkout -q --detach "$root"
git commit -qm rewrite --allow-empty
TESTED=$(git rev-parse HEAD)
export GREEN TESTED
git commit -qm landing --allow-empty
before=$(git rev-parse HEAD)
git commit -qm next --allow-empty
export GITHUB_REPOSITORY=test/repo
mkdir bin
# A run list without `--event push` also returns $DISPATCH: a workflow_dispatch on main that selected core only.
printf '%s\n' '#!/bin/bash' 'if [ "$1" = api ]; then' '  [[ "$2" == */"$TESTED"/status ]] && echo success' 'elif [[ " $* " != *" --event push "* && -n "${DISPATCH:-}" ]]; then' '  echo "$DISPATCH"' 'elif [[ " $* " == *" --limit 1 "* ]]; then' '  echo "$GREEN"' 'else' '  echo "${RUN_GREEN:-$GREEN}"' 'fi' > bin/gh
chmod +x bin/gh
export PATH="$scratch/bin:$PATH"
test "$(bash "$script" "$before" HEAD)" = "$TESTED"
echo 'PASS: rewrite selects tested ancestor across skipped landings'
export RUN_GREEN=$before
test "$(bash "$script" "$root" HEAD)" = "$before"
echo 'PASS: nearest successful run wins'
export GREEN=$root
test "$(bash "$script" "$before" HEAD)" = "$root"
echo 'PASS: ancestral last green retained'
export DISPATCH=$before
test "$(bash "$script" "$before" HEAD)" = "$root"
echo 'PASS: a dispatch on main never becomes the base'
unset DISPATCH
export GREEN=
test "$(bash "$script" "$before" HEAD)" = "$before"
echo 'PASS: unavailable green keeps event fallback'
