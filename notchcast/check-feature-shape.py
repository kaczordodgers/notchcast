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
    def mask(match):
        blank = re.sub(r"[^\n]", " ", match[0])
        return "0" + blank[1:] if match[0].startswith('"') else blank
    return re.sub(pattern, mask, source, flags=re.S)


def case_errors(code):
    tokens = [(match[0], code.count("\n", 0, match.start()) + 1)
              for match in re.finditer(r"[A-Za-z_]\w*|[^\s]", code)]
    errors = []
    scopes = []
    pending = None
    case_lines = set()
    for index, (token, line) in enumerate(tokens):
        if token in ("enum", "switch"):
            pending = {"kind": token, "name": tokens[index + 1][0], "cases": {}}
        elif token == "{":
            scopes.append(pending or {"kind": "block"})
            pending = None
        elif token == "}":
            if scopes:
                scopes.pop()
        elif token == "case":
            if line in case_lines:
                errors.append((line, "put each case declaration on its own line"))
            case_lines.add(line)
            if not scopes or scopes[-1]["kind"] not in ("enum", "switch"):
                continue
            scope = scopes[-1]
            end = index + 1
            names = []
            if scope["kind"] == "switch":
                while end < len(tokens) and tokens[end][0] not in (":", "{", "}", "case"):
                    end += 1
                pattern = tokens[index + 1:end]
                names = [(pattern[i + 1][0], pattern[i + 1][1])
                         for i in range(len(pattern) - 1) if pattern[i][0] == "."]
                if any(value == "," for value, _ in pattern):
                    errors.append((line, "multi-case arm; use one arm per feature"))
                if (end + 1 >= len(tokens) or tokens[end][0] != ":"
                        or tokens[end][1] != line or tokens[end + 1][1] != line):
                    errors.append((line, "keep each feature arm on one line"))
            else:
                while end < len(tokens) and re.fullmatch(r"[A-Za-z_]\w*", tokens[end][0]):
                    names.append(tokens[end])
                    end += 1
                    if end >= len(tokens) or tokens[end][0] != ",":
                        break
                    end += 1
                if len(names) > 1:
                    errors.append((line, "declare only one enum case per line"))
                if names and names[0][1] != line:
                    errors.append((line, "keep each enum case on one line"))
            for name, name_line in names:
                if name in scope["cases"]:
                    label = f".{name} in switch" if scope["kind"] == "switch" else f"{name} in {scope['name']}"
                    first = scope["cases"][name]
                    errors.append((name_line, f"repeated case {label} (first declared on line {first})"))
                else:
                    scope["cases"][name] = name_line
    return errors


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
        errors.extend(f"{path}:{line}: {message}" for line, message in case_errors(code))
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
    print("PASS: feature cases and switch arms use one line per feature, with no repeated cases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
