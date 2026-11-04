#!/bin/bash
# replant-ins.sh <new-branch> <base> <catalog-src-ref> <catalog-base-ref> <commit>...
# Cherry-picks commits onto base without catalog/generated/run-tests edits, then inserts the catalog keys
# that <catalog-src-ref> adds over <catalog-base-ref> as text (insertion only) in one strings commit.
set -e
new=$1; base=$2; src=$3; old=$4; shift 4
C=Tinycast/Resources/Localizable.xcstrings
git switch -q -c "$new" "$base"
for c in "$@"; do
  git cherry-pick -n "$c" >/dev/null 2>&1 || true
  git restore --staged --worktree --source=HEAD -- $C Tinycast.xcodeproj/project.pbxproj Scripts/run-tests.sh README.md README.upstream.md Tinycast/Resources/RaycastRuntime.generated.js 2>/dev/null || true
  left=$(git diff --name-only --diff-filter=U)
  [ -z "$left" ] || { echo "UNRESOLVED in $c: $left"; exit 1; }
  if git diff --cached --quiet; then echo "empty: $c"; continue; fi
  git commit -q -C "$c" >/dev/null 2>&1 || { echo "commit refused for $c"; git commit -C "$c"; exit 1; }
done
t=$(mktemp -d); git show "$src:$C" > "$t/src"; git show "$old:$C" > "$t/old"
python3 notchcast/xins.py "$C" "$t/src" "$t/old"
git diff --numstat -- $C
if ! git diff --quiet -- $C; then git add $C; git commit -q -m "Notchcast: ${STRINGS_MSG:-strings}" >/dev/null 2>&1 || { echo "strings commit refused"; exit 1; }; fi
git log --oneline "$base"..
