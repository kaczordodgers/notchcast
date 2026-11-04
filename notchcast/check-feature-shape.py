#!/usr/bin/env python3
"""Keep feature registrations safe for append-only union merges."""

import re
import sys
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FEATURE = Path("Tinycast/Features/Notchcast/Core/NotchcastFeature.swift")
GROUPS = FEATURE.with_name("NotchcastFeature+SettingsGroup.swift")
# Union-merged lists: each entry's identity, so an edited line a union kept twice is caught.
LISTS = {
    Path("Tinycast/Features/SettingsBackup/Model/ForkSettingsBackupSchema.swift"): r'^"([^"]+)"',
    Path("Tinycast/Features/Notchcast/Core/NotchcastCore+Modules.swift"): r"module: ([\w.]+)",
    Path("Tinycast/Features/Notchcast/Settings/NotchcastSettingsSearch.swift"): r"^(.*?)(?:, keywords: .*)?\),$",
}


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


PREFERENCES = Path("Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift")


def preference_errors(source):
    """Stored settings and init assignments: one line each, each name once."""
    errors = []
    lines = source.split("\n")
    code = mask_literals(source).split("\n")
    if sum(1 for line in code if re.match(r"\s*final class NotchcastPreferences\b", line)) != 1:
        errors.append((1, "expected one NotchcastPreferences class"))
    depth = 0
    in_class = in_init = False
    names = {}
    assigned = {}
    for number, (line, masked) in enumerate(zip(lines, code), 1):
        stripped = masked.strip()
        balance = sum(masked.count(c) for c in "{([") - sum(masked.count(c) for c in "})]")
        if depth == 0 and re.match(r"(?:@\w+\s+)*final class NotchcastPreferences\b", stripped):
            in_class = True
        elif in_class and depth == 1 and stripped.startswith("init("):
            in_init = True
        elif in_class and depth == 1 and re.match(r"(?:@\w+\s+)*(?:private\s+|fileprivate\s+)?(?:let|var)\s", stripped):
            if balance:
                errors.append((number, "keep each setting on one line"))
            name = re.search(r"\b(?:let|var)\s+(\w+)", stripped)[1]
            if name in names:
                errors.append((number, f"repeated setting {name} (first on line {names[name]})"))
            names.setdefault(name, number)
        elif in_init and depth == 2 and stripped and stripped != "}":
            if balance:
                errors.append((number, "keep each init statement on one line"))
            target = re.match(r"(?:self\.)?(\w+)\s*=[^=]", stripped)
            if target:
                if target[1] in assigned:
                    errors.append((number, f"repeated assignment {target[1]} (first on line {assigned[target[1]]})"))
                assigned.setdefault(target[1], number)
        depth += balance - (masked.count("(") + masked.count("[") - masked.count(")") - masked.count("]"))
        if depth <= 1:
            in_init = False
        if depth == 0:
            in_class = False
    return errors


def list_errors(source, identity):
    errors = []
    code = mask_literals(source).split("\n")
    names = {}
    entries = {}
    depth = 0
    for number, (line, masked) in enumerate(zip(source.split("\n"), code), 1):
        declared = re.match(r"\s*(?:private )?static (?:let|var) (\w+)", masked)
        if declared:
            name = declared[1]
            if name in names:
                errors.append((number, f"repeated static {name} (first declared on line {names[name]})"))
            names.setdefault(name, number)
        balance = sum(masked.count(c) for c in "([") - sum(masked.count(c) for c in ")]")
        if depth and masked.strip() != "]":
            if balance or not masked.rstrip().endswith(","):
                errors.append((number, "keep each list entry on one line, ending with a comma"))
            else:
                key = re.search(identity, line.strip())
                key = key[1] if key else line.strip()
                if key in entries:
                    errors.append((number, f"repeated entry {key} (first on line {entries[key]})"))
                entries.setdefault(key, number)
        if masked.rstrip().endswith("[") and balance == 1:
            depth = 1
        elif depth and masked.strip() == "]":
            depth = 0
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
    for path, identity in LISTS.items():
        try:
            source = (root / path).read_text()
        except OSError as error:
            errors.append(f"{path}:1: {error}")
            continue
        if path.name == "ForkSettingsBackupSchema.swift":
            source = re.sub(r"(?s)^.*?(?=    static let allowed:)", lambda m: "\n" * m[0].count("\n"), source)
        errors.extend(f"{path}:{line}: {message}" for line, message in list_errors(source, identity))
    try:
        source = (root / PREFERENCES).read_text()
    except OSError as error:
        errors.append(f"{PREFERENCES}:1: {error}")
    else:
        errors.extend(f"{PREFERENCES}:{line}: {message}" for line, message in preference_errors(source))
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
    if subprocess.run([sys.executable, str(ROOT / "notchcast/check-switch-paths.py"),
                       str(Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT)]).returncode:
        errors.append("switch user paths failed")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("PASS: feature cases, switch arms, modules, search entries and settings use one line each, with no repeats")
    return 0


if __name__ == "__main__":
    sys.exit(main())
