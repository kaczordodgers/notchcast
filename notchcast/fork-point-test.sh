#!/bin/bash
set -euo pipefail
script=$(cd "$(dirname "$0")" && pwd)/fork-point.sh
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
git init -q
export GIT_AUTHOR_NAME=Test GIT_COMMITTER_NAME=Test
export GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_EMAIL=test@example.com
git commit -qm root --allow-empty
base=$(git rev-parse HEAD)
git commit -qm old --allow-empty
old=$(git rev-parse HEAD)
git commit -qm branch --allow-empty
head=$(git rev-parse HEAD)
git checkout -q --detach "$base"
git commit -qm rewrite --allow-empty
onto=$(git rev-parse HEAD)
test "$(bash "$script" "$onto" "$head")" = "$base"
git update-ref refs/notchcast/synced/old "$old"
test "$(bash "$script" "$onto" "$head")" = "$old"
echo 'PASS: replaced main fork point'
git merge -q --no-edit "$head"
test "$(bash "$script" HEAD "$head")" = "$head"
echo 'PASS: updated branch keeps plain base'
