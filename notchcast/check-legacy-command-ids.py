#!/usr/bin/env python3
"""Protect persisted command identities in the shipped feature sources."""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMAND = Path("Tinycast/Features/Notchcast/Island/IslandController+Command.swift")


def check(root):
    try:
        source = (root / COMMAND).read_text()
    except OSError as error:
        return [f"{COMMAND}: {error}"]
    pattern = r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"'
    source = re.sub(pattern, lambda match: match[0] if match[0].startswith('"') else " ",
                    source, flags=re.S)
    ids = re.findall(r'\blegacyID\s*:\s*("(?:\\.|[^"\\])*"|[^\s,)]+)', source)
    if ids != ['"command:toggle-island"']:
        return [f'{COMMAND}: expected legacyID: "command:toggle-island"; persisted identity changed']
    return []


def main():
    if len(sys.argv) > 2:
        print(f"usage: {sys.argv[0]} [repository-root]", file=sys.stderr)
        return 2
    errors = check(Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("PASS: Toggle Island retains legacy command ID command:toggle-island")
    return 0


if __name__ == "__main__":
    sys.exit(main())
