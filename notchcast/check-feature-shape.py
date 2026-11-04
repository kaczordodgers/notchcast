#!/usr/bin/env python3
"""Keep feature registrations safe for append-only union merges."""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FEATURE = Path("Tinycast/Features/Notchcast/Core/NotchcastFeature.swift")
GROUPS = FEATURE.with_name("NotchcastFeature+SettingsGroup.swift")


def mask_literals(source):
    pattern = r'//[^\n]*|/\*.*?\*/|""".*?"""|"(?:\\.|[^"\\])*"'
    return re.sub(pattern, lambda match: re.sub(r"[^\n]", " ", match[0]), source, flags=re.S)


def check(root):
    errors = []
    declarations = {"NotchcastFeature": [], "SettingsGroup": []}
    for path in (FEATURE, GROUPS):
        try:
            source = (root / path).read_text()
        except OSError as error:
            errors.append(f"{path}:1: {error}")
            continue
        code = mask_literals(source)
        for name in declarations:
            for match in re.finditer(rf"\benum\s+{name}\b", code):
                declarations[name].append((path, code.count("\n", 0, match.start()) + 1))
        offset = 0
        for number, line in enumerate(code.splitlines(keepends=True), 1):
            cases = list(re.finditer(r"\bcase\b", line))
            if len(cases) > 1:
                errors.append(f"{path}:{number}: put each case declaration on its own line")
            for match in cases:
                tail = line[match.end():].strip()
                if tail.startswith("."):
                    arm = code[offset + match.end():].split(":", 1)[0]
                    if "," in arm:
                        errors.append(f"{path}:{number}: multi-case arm; use one arm per feature")
                    if ":" not in tail or not tail.split(":", 1)[1].strip():
                        errors.append(f"{path}:{number}: keep each feature arm on one line")
                elif "," in tail:
                    errors.append(f"{path}:{number}: declare only one enum case per line")
            offset += len(line)
    for name, locations in declarations.items():
        if len(locations) != 1:
            path, number = locations[-1] if locations else (FEATURE, 1)
            errors.append(f"{path}:{number}: expected one {name} enum, found {len(locations)}")
    return errors


def main():
    if len(sys.argv) > 2:
        print(f"usage: {sys.argv[0]} [repository-root]", file=sys.stderr)
        return 2
    errors = check(Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("PASS: feature cases and switch arms use one line per feature")
    return 0


if __name__ == "__main__":
    sys.exit(main())
