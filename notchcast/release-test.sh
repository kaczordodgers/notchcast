#!/bin/bash
set -euo pipefail
exec ruby "$(dirname "$0")/release-test.rb" "$@"
