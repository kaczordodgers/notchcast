#!/usr/bin/env python3
"""Detect entries lost during a three-way conflict resolution without compiling.

Resolver worker, before pushing a conflict-resolution branch: python3 notchcast/check-entry-lists.py --ours origin/main --theirs <old PR head>
"""

import argparse
import re
import subprocess
import sys

FILES = (
    "Tinycast/Features/Notchcast/Core/NotchcastFeature.swift",
    "Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift",
    "Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift",
    "Tinycast/Features/SettingsBackup/Model/ForkSettingsBackupSchema.swift",
)


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def entries(rev, path):
    exists = git("ls-tree", rev, "--", path)
    if not exists:
        return set()
    source = git("show", f"{rev}:{path}")
    source = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                    lambda m: m[0] if m[0].startswith('"') else re.sub(r"[^\n]", " ", m[0]),
                    source, flags=re.S)
    return {line.strip() for line in source.splitlines()
            if line.strip() and not re.fullmatch(r"[{}\[\](),;\s]+", line)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--result", default="HEAD")
    parser.add_argument("--ours", required=True)
    parser.add_argument("--theirs", required=True)
    parser.add_argument("--base")
    parser.add_argument("--file", action="append", default=[])
    args = parser.parse_args()
    result, ours, theirs = (git("rev-parse", "--verify", f"{rev}^{{commit}}")
                            for rev in (args.result, args.ours, args.theirs))
    base = git("rev-parse", "--verify", f"{args.base}^{{commit}}") if args.base else git("merge-base", ours, theirs)
    dropped = 0
    for path in dict.fromkeys((*FILES, *args.file)):
        b, o, t, r = (entries(rev, path) for rev in (base, ours, theirs, result))
        required = (o & t) | (o - b) | (t - b)
        for entry in sorted(required - r):
            side = "ours and theirs" if entry in o & t else "ours" if entry in o else "theirs"
            print(f"{path}: dropped from {side}: {entry}")
            dropped += 1
        for entry in sorted(r - (o | t)):
            print(f"info: {path}: result-only: {entry}")
    print(f"entry lists: {'FAIL' if dropped else 'PASS'} ({dropped} dropped entries)")
    return bool(dropped)


if __name__ == "__main__":
    sys.exit(main())
