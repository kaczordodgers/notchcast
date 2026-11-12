#!/bin/bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=notchcast/config.env
source notchcast/config.env
export CI_SKIP_TESTS
python3 - "$@" <<'PY'
import fnmatch
import os
import subprocess
import sys

sys.path.insert(0, 'notchcast')
from harness_inputs import harnesses

if len(sys.argv) != 3:
    sys.exit('usage: changed-harnesses.sh <base> <head>')
# --no-renames lists both ends of a move; a moved source leaves the harness that compiled it.
changed = set(subprocess.check_output(
    ['git', 'diff', '--name-only', '--no-renames', '-z', sys.argv[1], sys.argv[2]], text=True).split('\0')) - {''}
selected = {'notchcast-core-test'}
for path, inputs in harnesses():
    name = path.stem
    patterns = inputs.patterns + inputs.reads
    # Against the changed paths, not the tree: a deleted source no longer exists to glob.
    touched = any(fnmatch.fnmatchcase(file, pattern) for pattern in patterns for file in changed)
    if str(path) in changed or touched:
        selected.add(name)
# CI_SKIP_TESTS names what the hosted VM cannot run; a Mac runs them, and core always runs.
skipped = set(os.environ['CI_SKIP_TESTS'].split()) if os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted' else set()
print('\n'.join(sorted((selected - skipped) | {'notchcast-core-test'})))
PY
