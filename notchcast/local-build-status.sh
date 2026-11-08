#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/config.env"
local_build_green() {
    gh api --paginate "repos/$FORK_REPO/commits/$1/statuses?per_page=100" \
        --jq ".[] | select(.context == \"build/local\" and .creator.login == \"${FORK_REPO%%/*}\")" \
        | jq -s -e --arg url "https://api.github.com/repos/$FORK_REPO/statuses/$1" \
            'sort_by(.id) | last | .url == $url and .state == "success"' >/dev/null
}
