#!/usr/bin/env python3
"""Check every backup key is declared once: feature switches in the schema, a feature's own keys in its folder."""

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
# The capture module cannot hold a key file yet; SettingsBackup's own restore writes the editor keys.
SCHEMA_KEYS = {"notchcast.colorPicker.format",
               "notchcast.screenshot.destination", "notchcast.screenshot.folder",
               "notchcast.editor.font", "notchcast.editor.theme", "notchcast.editor.pairsAutomatically"}
KEYS_FILE = re.compile(shape.DESCRIPTOR_FILE.pattern.replace("Descriptor", "BackupKeys"))
KEYS_DECLARATION = re.compile(r"extension\s+NotchcastFeature\.BackupKeys\b|\bBackupKeys\s*(?:\.init\s*)?\("
                              r"|\bstatic\s+(?:let|var)\s+\w+\s*:\s*(?:NotchcastFeature\.)?BackupKeys\b"
                              r"|->\s*(?:NotchcastFeature\.)?BackupKeys\b")
SECRET_NAME = re.compile(r"(?i)soloist|spotify|api.?key|secret|token|password")
SECRET_ALLOWED = "is named like a secret; a backup never carries one, so list it as excluded"


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
    return source[start + 1:end - 1], source.count("\n", 0, start)


def entries(source, offset, keyed):
    """String keys at the top level of a list body, each with its line."""
    code = shape.mask_literals(source)
    found = []
    depth = 0
    for index, char in enumerate(code):
        depth += (char in "([{") - (char in ")]}")
        if char != "0" or source[index] != '"' or depth:
            continue
        value, length = json.JSONDecoder().raw_decode(source[index:])
        follower = code[index + length:].lstrip(" ")[:1]
        if follower == ":" or not keyed:
            found.append((value, offset + source.count("\n", 0, index) + 1))
    return found


def features(root):
    enum, _ = body((root / FEATURE).read_text(), r"\benum\s+NotchcastFeature\b", "{", "}")
    masked = shape.mask_literals(enum)
    found = []
    for match in re.finditer(r"^\s*case\s+(\w+)(?:\s*=\s*(0))?", masked, re.M):
        raw = match[1]
        if match[2]:
            raw, _ = json.JSONDecoder().raw_decode(enum[match.start(2):])
        found.append((match[1], raw))
    if not found:
        raise ValueError(f"no feature cases in {FEATURE}")
    return found


def described(root):
    hub = shape.mask_literals((root / shape.DESCRIPTORS).read_text())
    return set(re.findall(r"^\s*\.(\w+): \.\w+,$", hub, re.M))


def check(root):
    errors = []
    raw_values = {raw for _, raw in features(root)}
    schema = (root / SCHEMA).read_text()
    declared = {}
    for name, keyed in (("listedAllowed", True), ("listedExcluded", False)):
        source, offset = body(schema, rf"\bstatic\s+let\s+{name}\b[^=]*=", "[", "]")
        for key, line in entries(source, offset, keyed):
            declared.setdefault(key, []).append(f"{SCHEMA}:{line}")
            if keyed and SECRET_NAME.search(key):
                errors.append(f"{SCHEMA}:{line}: {key} {SECRET_ALLOWED}")
            if key not in raw_values and key not in SCHEMA_KEYS:
                errors.append(f"{SCHEMA}:{line}: {key} is a feature's own key; "
                              "declare it in <Name>BackupKeys.swift in that feature's folder")
    listing, offset = body(schema, r"\bstatic\s+let\s+featureKeys\b[^=]*=", "[", "]")
    listed = {}
    for number, text in enumerate(shape.mask_literals(listing).split("\n"), offset + 1):
        match = re.fullmatch(r"\s*\.(\w+),\s*", text)
        if not match:
            if text.strip():
                errors.append(f"{SCHEMA}:{number}: list one feature per featureKeys line, as .name,")
        elif match[1] in listed:
            errors.append(f"{SCHEMA}:{number}: .{match[1]} listed twice in featureKeys (first at line {listed[match[1]]})")
        else:
            listed[match[1]] = number
    features_described = described(root)
    files = set()
    for path in sorted((root / "Tinycast/Features").rglob("*.swift")):
        relative = path.relative_to(root)
        source = path.read_text()
        if "Keys" not in source:
            continue
        code = shape.mask_literals(source)
        declaration = KEYS_DECLARATION.search(code)
        place = KEYS_FILE.fullmatch(relative.as_posix())
        if declaration and not place and relative != SCHEMA:
            errors.append(f"{relative}:{code.count(chr(10), 0, declaration.start()) + 1}: declare backup keys in "
                          "Tinycast/Features/<its folder>/<Name>BackupKeys.swift")
            continue
        if not place:
            continue
        feature = place[1][:1].lower() + place[1][1:]
        files.add(feature)
        names = re.findall(r"^\s*static let (\w+)\b", code, re.M)
        if not declaration or names != [feature]:
            errors.append(f"{relative}:1: declare exactly one .{feature} of NotchcastFeature.BackupKeys")
            continue
        if feature not in features_described:
            errors.append(f"{relative}:1: .{feature} has no descriptor; a key file belongs to a described feature")
        elif not path.with_name(f"{place[1]}Descriptor.swift").exists():
            errors.append(f"{relative}:1: put it beside {place[1]}Descriptor.swift")
        if feature not in listed:
            errors.append(f"{relative}:1: list .{feature}, in featureKeys in {SCHEMA}")
        for label, keyed in (("allowed", True), ("excluded", False)):
            keys, offset = body(source, rf"\b{label}\s*:", "[", "]")
            for key, line in entries(keys, offset, keyed):
                declared.setdefault(key, []).append(f"{relative}:{line}")
                if keyed and SECRET_NAME.search(key):
                    errors.append(f"{relative}:{line}: {key} {SECRET_ALLOWED}")
    errors.extend(f"{SCHEMA}:{line}: .{name} has no {name[:1].upper() + name[1:]}BackupKeys.swift"
                  for name, line in listed.items() if name not in files)
    for key, places in declared.items():
        if len(places) > 1:
            errors.append(f"{places[-1]}: {key} declared twice (first at {places[0]})")
    for name, raw in features(root):
        if raw not in declared:
            errors.append(f"{name} ({raw}): unclassified; edit {SCHEMA}")
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
