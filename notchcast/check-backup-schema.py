#!/usr/bin/env python3
"""Check feature raw values are classified exactly once by the backup schema."""

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("shape", Path(__file__).with_name("check-feature-shape.py"))
shape = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shape)
ROOT = Path(__file__).resolve().parents[1]
FEATURE = Path("Tinycast/Features/Notchcast/Core/NotchcastFeature.swift")
SCHEMA = Path("Tinycast/Features/SettingsBackup/Model/ForkSettingsBackupSchema.swift")


def body(source, pattern, opening, closing):
    code = shape.mask_literals(source)
    match = re.search(pattern, code)
    if match is None:
        raise ValueError(f"missing declaration: {pattern}")
    start = code.index(opening, match.end())
    depth = 1
    end = start + 1
    while depth and end < len(code):
        depth += (code[end] == opening) - (code[end] == closing)
        end += 1
    if depth:
        raise ValueError("unterminated declaration")
    return source[start + 1:end - 1]


def check(root):
    enum = body((root / FEATURE).read_text(), r"\benum\s+NotchcastFeature\b", "{", "}")
    masked = shape.mask_literals(enum)
    features = []
    for match in re.finditer(r"^\s*case\s+(\w+)(?:\s*=\s*(0))?", masked, re.M):
        raw = match[1]
        if match[2]:
            raw, _ = json.JSONDecoder().raw_decode(enum[match.start(2):])
        features.append((match[1], raw))
    if not features:
        raise ValueError(f"no feature cases in {FEATURE}")
    schema = (root / SCHEMA).read_text()
    classified = []
    for name in ("allowed", "excluded"):
        entries = body(schema, rf"\bstatic\s+let\s+{name}\b[^=]*=", "[", "]")
        code = shape.mask_literals(entries)
        pattern = r"^\s*(0)\s*:" if name == "allowed" else r"^\s*(0)\s*[,\n]"
        classified.append({json.JSONDecoder().raw_decode(entries[m.start(1):])[0]
                           for m in re.finditer(pattern, code, re.M)})
    errors = []
    for name, raw in features:
        count = sum(raw in values for values in classified)
        if count != 1:
            label = "unclassified" if count == 0 else "doubly classified"
            errors.append(f"{name} ({raw}): {label}; edit {SCHEMA}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        errors = check(args.root)
    except (OSError, ValueError) as error:
        parser.exit(1, f"backup schema: {error}\n")
    for error in errors:
        print(error)
    print(f"backup schema: {'FAIL' if errors else 'PASS'}")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
