#!/bin/bash
# UI mistakes we add, found by enmerasoftware/ai-design-check (SwiftUI rules: spacing and radius scale, Dynamic Type,
# tap targets, icon-button names, sentence case, emoji, heavy shadows...). Upstream's own findings are not ours: the
# checker runs on the upstream base first and its counts become the baseline, so only findings our commits add are
# reported (counted per file and rule). Errors fail; warnings are shown.
# Usage: design-check.sh <base-commit> [--staged]   (default: HEAD; --staged: the index, for the pre-commit hook)
set -euo pipefail
BASE="${1:?base commit (merge-base with upstream main)}"
TOP="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "$TOP/notchcast/config.env"
DIRS=(Tinycast)
TARGET=HEAD
[ "${2:-}" = --staged ] && TARGET="$(git write-tree)"
command -v npx >/dev/null || { echo "design-check: npx (Node 20+) is needed" >&2; exit 1; }
CHECK=(npx -y "@enmera/ai-design-check@$DESIGN_CHECK_VERSION")
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/base" "$WORK/ours"
# Files, not pipes: tar exits at the end marker, and git archive then dies of SIGPIPE.
git archive -o "$WORK/base.tar" "$BASE" "${DIRS[@]}"
git archive -o "$WORK/ours.tar" "$TARGET" "${DIRS[@]}"
tar -xf "$WORK/base.tar" -C "$WORK/base"
tar -xf "$WORK/ours.tar" -C "$WORK/ours"
# Island and page values come from the island kit (notchcast/check-kit.py).
python3 "$TOP/notchcast/check-kit.py" --root "$WORK/ours"
# The baseline file lands in the base copy (the checker writes it to its working directory); its exit code is the
# base's own findings, not ours.
(cd "$WORK/base" && "${CHECK[@]}" --write-baseline "${DIRS[@]}" >/dev/null) || true
cp "$WORK/base/.ai-design-check-baseline.json" "$WORK/ours/"
FORMAT=()
[ -n "${GITHUB_ACTIONS:-}" ] && FORMAT=(--format github)
cd "$WORK/ours" && "${CHECK[@]}" ${FORMAT[@]+"${FORMAT[@]}"} "${DIRS[@]}"
