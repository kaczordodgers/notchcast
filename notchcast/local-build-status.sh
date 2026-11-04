#!/bin/bash
local_build_green() {
    gh api --paginate "repos/kaczordodgers/notchcast/commits/$1/statuses?per_page=100" \
        --jq '.[] | select(.context == "build/local" and .creator.login == "kaczordodgers")' \
        | jq -s -e --arg url "https://api.github.com/repos/kaczordodgers/notchcast/statuses/$1" \
            'sort_by(.id) | last | .url == $url and .state == "success"' >/dev/null
}
