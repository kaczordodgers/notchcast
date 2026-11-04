#!/usr/bin/env python3
"""Keep feature registrations safe for append-only union merges."""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FEATURE = Path("Tinycast/Features/Notchcast/Core/NotchcastFeature.swift")
GROUPS = FEATURE.with_name("NotchcastFeature+SettingsGroup.swift")
LOGIC = FEATURE.with_name("NotchcastFeature+Logic.swift")  # not merge=union: multi-line logic lives here
# Union-merged lists: each entry's identity, so an edited line a union kept twice is caught.
LISTS = {
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
                    errors.append((line, "keep each feature arm on one line" + UNION_HINT))
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
                    errors.append((line, "keep each enum case on one line" + UNION_HINT))
            for name, name_line in names:
                if name in scope["cases"]:
                    label = f".{name} in switch" if scope["kind"] == "switch" else f"{name} in {scope['name']}"
                    first = scope["cases"][name]
                    errors.append((name_line, f"repeated case {label} (first declared on line {first})"))
                else:
                    scope["cases"][name] = name_line
    return errors


UNION_HINT = ("; a duplicated block came from a union merge: take main's file "
              "(git checkout origin/main -- <file>) and add your lines")
ARM = re.compile(r"(?:case\s+\.\w+|default)\s*:\s*\S")


def body_errors(code):
    """Union feature files hold cases and `switch self` bodies of one-line arms; nothing else spans lines.

    A union merge appends lines it cannot place: a second multi-line body after ours (Swift then returns the
    last expression and only warns), a body inside a switch, or a repeated property header. Logic lives in
    NotchcastFeature+Logic.swift, which is not merge=union, so git reports a real conflict there instead.
    """
    errors = []
    lines = code.split("\n")
    depth = 0
    names = {}
    index = 0
    while index < len(lines):
        stripped = lines[index].strip()
        opens = stripped.count("{") - stripped.count("}")
        member = re.match(r"(?:(?:public|private|fileprivate|internal|static)\s+)*(var|func|init|subscript)\b\s*(\w*)", stripped)
        if member and depth >= 1:
            name = member[2] or member[1]
            if name in names:
                errors.append((index + 1, f"repeated {member[1]} {name} (first on line {names[name]})" + UNION_HINT))
            names.setdefault(name, index + 1)
            if opens > 0:
                end, level = index + 1, opens
                while end < len(lines) and level > 0:
                    level += lines[end].count("{") - lines[end].count("}")
                    end += 1
                body = [(number + 1, lines[number].strip()) for number in range(index + 1, end - 1)
                        if lines[number].strip()]
                if not body or body[0][1] != "switch self {" or body[-1][1] != "}":
                    errors.append((index + 1, f"{name}: a body over several lines must be one `switch self` "
                                              "in a union file; move logic to NotchcastFeature+Logic.swift" + UNION_HINT))
                else:
                    errors.extend((number, f"{name}: only one-line `case .x: value` arms belong in its switch" + UNION_HINT)
                                  for number, line in body[1:-1] if not ARM.match(line))
                index = end
                continue
        depth += opens
        index += 1
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
        errors.extend(f"{path}:{line}: {message}" for line, message in body_errors(code))
    for path, identity in LISTS.items():
        try:
            source = (root / path).read_text()
        except OSError as error:
            errors.append(f"{path}:1: {error}")
            continue
        errors.extend(f"{path}:{line}: {message}" for line, message in list_errors(source, identity))
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
    print("PASS: feature cases, switch arms, modules and search entries use one line each, with no repeats")
    return 0


if __name__ == "__main__":
    sys.exit(main())
