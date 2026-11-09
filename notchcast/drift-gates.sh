#!/bin/bash
# Sourced by land.sh and local-ci.sh; the caller sets scratch and top, cwd is the merged tree.
refuse() { echo "REFUSED: $*" >&2; exit 1; }
prepare_drift_tools() {
    drift_tools="$scratch/gates-$1"
    mkdir -p "$drift_tools"
    git archive "$1" notchcast | tar -x -C "$drift_tools"
    drift_tools="$drift_tools/notchcast"
    if [ ! -f "$drift_tools/check-drift.py" ]; then
        drift_tools="$top/notchcast"
    fi
}
check_drift() {
    local onto=$1 tools=$2
    if python3 "$tools/check-drift.py" --root "$PWD"; then return 0; fi
    git cat-file -e "$onto:notchcast/drift-baseline.json" 2>/dev/null || refuse 'drift'
    git worktree add --quiet --detach "$scratch/base" "$onto"
    if ! python3 "$tools/check-drift.py" --root "$scratch/base" >/dev/null 2>&1; then
        echo "WARN: main is already red: ${onto:0:8} fails the drift gates too; fix main before landing" >&2
    fi
    git worktree remove --force "$scratch/base"
    refuse 'drift'
}
run_drift_gates() {
    local onto=$1
    prepare_drift_tools "$onto"
    python3 "$drift_tools/check-drift.py" --root "$PWD" --compare-base "$onto" || refuse 'drift baseline grew'
    check_drift "$onto" "$drift_tools"
}
