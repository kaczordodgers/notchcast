#!/bin/bash
# Fetches upstream's main into refs/remotes/upstream/main of the repository in the current directory.
# Arguments are git fetch options (--no-tags).
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/config.env"
git fetch -q "$@" "https://github.com/$UPSTREAM_REPO.git" "+refs/heads/main:refs/remotes/upstream/main"
