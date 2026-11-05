#!/bin/bash
set -euo pipefail
before=$1
head=$2
# Push runs only: a workflow_dispatch on main selects from main itself (core only), so it proves nothing about pushes.
green=$(gh run list -R "$GITHUB_REPOSITORY" --workflow main-harnesses.yml --branch main --event push --status success \
    --limit 1 --json headSha --jq '.[0].headSha // empty') || green=
if [ -n "$green" ]; then
    if git merge-base --is-ancestor "$green" "$head" 2>/dev/null; then
        before=$green
    else
        runs=$(gh run list -R "$GITHUB_REPOSITORY" --workflow main-harnesses.yml --branch main --event push --status success \
            --limit 100 --json headSha --jq '.[].headSha') || runs=
        for candidate in $(git rev-list --first-parent --max-count=50 "$head^"); do
            if [[ $'\n'"$runs"$'\n' == *$'\n'"$candidate"$'\n'* ]]; then
                before=$candidate
                break
            fi
            tested=$(gh api "repos/$GITHUB_REPOSITORY/commits/$candidate/status" \
                --jq '[.statuses[] | select(.context == "notchcast/tested")][0].state // empty') || tested=
            if [ "$tested" = success ]; then
                before=$candidate
                break
            fi
        done
    fi
fi
echo "$before"
