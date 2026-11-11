#!/usr/bin/env python3
"""Check every backup key is declared once: a switch by its feature's backedUp flag, other keys in a feature's folder.

A key file with a snapshot writes exactly the keys it allows, and one with an apply reads exactly those."""

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
LIST = FEATURE.with_name("NotchcastBackupKeys.swift")
KEYS_FILE = re.compile(shape.DESCRIPTOR_FILE.pattern.replace("Descriptor", "BackupKeys"))
KEYS_DECLARATION = re.compile(r"extension\s+NotchcastFeature\.BackupKeys\b|\bBackupKeys\s*(?:\.init\s*)?\("
                              r"|\bstatic\s+(?:let|var)\s+\w+\s*:\s*(?:NotchcastFeature\.)?BackupKeys\b"
                              r"|->\s*(?:NotchcastFeature\.)?BackupKeys\b")
CONFIDENTIAL_LOOKING = re.compile(r"(?i)soloist|spotify|api.?key|secret|token|password")
NOT_FOR_BACKUP = "this allowed key is named like a secret; a backup never carries one, so list it as excluded"


def span(source, pattern, opening, closing):
    """Where the bracketed body after a declaration starts and ends."""
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
    return start + 1, end - 1


def body(source, pattern, opening, closing):
    start, end = span(source, pattern, opening, closing)
    return source[start:end], source.count("\n", 0, start)


def key_at(source, code, index):
    """The key written at index, a string literal or an owner's constant, and its length."""
    if code[index] == "0" and source[index] == '"':
        value, length = json.JSONDecoder().raw_decode(source[index:])
        return json.dumps(value), length
    match = re.match(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*", code[index:])
    # A bare capitalised name is a type, as in [String: Any].
    if match and (match[0][0].islower() or "." in match[0]):
        return match[0], match.end()
    return None, 0


def entries(source, offset, keyed):
    """Keys at the top level of a list body, each with its line."""
    code = shape.mask_literals(source)
    found = []
    depth = 0
    start = True
    for index, char in enumerate(code):
        if start and not depth and not char.isspace():
            key, length = key_at(source, code, index)
            follower = code[index + length:].lstrip()[:1]
            if key and (follower == ":" if keyed else follower in ("", ",")):
                found.append((key, offset + source.count("\n", 0, index) + 1))
            start = False
        depth += (char in "([{") - (char in ")]}")
        if char == "," and not depth:
            start = True
    return found


def value(key, *folders):
    """The string a key stands for: itself, or the owner's constant read from the feature's folder, then the hub's."""
    if key.startswith('"'):
        return json.loads(key)
    *owner, name = key.split(".")
    for folder in folders:
        for path in sorted(folder.rglob("*.swift")):
            source = path.read_text()
            code = shape.mask_literals(source)
            match = re.search(rf"\blet\s+{name}\s*=\s*0", code)
            if match and (not owner or re.search(rf"\b(?:class|struct|enum|actor|extension)\s+{owner[-1]}\b", code)):
                return json.JSONDecoder().raw_decode(source[match.end() - 1:])[0]
    raise ValueError(f"{key}: no string constant {name} under {folders[0].name}/")


def switch_flags(root):
    """Each place a feature says whether a backup carries its switch: descriptor, hub arm or the schema's waiting list."""
    stated = []
    for path in sorted((root / "Tinycast/Features").rglob("*Descriptor.swift")):
        relative = path.relative_to(root)
        source = path.read_text()
        name = re.search(r"^\s*static let (\w+) = Self\($", source, re.M)
        if name and shape.DESCRIPTOR_FILE.fullmatch(relative.as_posix()):
            stated.extend((name[1], flag[1], f"{relative}:{source.count(chr(10), 0, flag.start(1)) + 1}")
                          for flag in re.finditer(r"^\s*backedUp: (true|false),?$", source, re.M))
    source = (root / FEATURE).read_text()
    member = re.search(r"^    var backedUp\b.*?(?=^    var |\Z)", source, re.M | re.S)
    for arm in re.finditer(r"^\s*case \.(\w+): (true|false)$", member[0] if member else "", re.M):
        stated.append((arm[1], arm[2], f"{FEATURE}:{source.count(chr(10), 0, member.start() + arm.start()) + 1}"))
    source = (root / SCHEMA).read_text()
    stated.extend((line[1], line[2], f"{SCHEMA}:{source.count(chr(10), 0, line.start(1)) + 1}")
                  for line in re.finditer(r"^\s*\.(\w+): (true|false),$", source, re.M))
    return stated


def live_keys(source, spans):
    """Keys a key file writes into dictionaries and reads from `values`, outside its key lists."""
    code = list(shape.mask_literals(source))
    for start, end in spans:
        code[start - 1:end + 1] = [char if char == "\n" else " " for char in code[start - 1:end + 1]]
    code = "".join(code)
    written, read = {}, {}
    for index, char in enumerate(code):
        if char != "[":
            continue
        line = code.count("\n", 0, index) + 1
        if re.match(r"[\w\])?!]", code[index - 1]):
            key, _ = key_at(source, code, index + 1)
            if key and code.endswith("values", 0, index):
                read.setdefault(key, line)
        elif not code.endswith(".object(", 0, index):
            depth = 1
            end = index + 1
            while depth and end < len(code):
                depth += (code[end] == "[") - (code[end] == "]")
                end += 1
            for key, at in entries(source[index + 1:end - 1], line - 1, True):
                written.setdefault(key, at)
    return written, read


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
    raw_values = dict(features(root))
    hub = root / FEATURE.parent
    declared = {}
    for name, flag, place in switch_flags(root):
        if name not in raw_values:
            errors.append(f"{place}: .{name} is no feature")
            continue
        declared.setdefault(raw_values[name], []).append(place)
        if flag == "true" and CONFIDENTIAL_LOOKING.search(raw_values[name]):
            errors.append(f"{place}: {NOT_FOR_BACKUP}")
    listing, offset = body((root / LIST).read_text(), r"\bstatic\s+let\s+all\b[^=]*=", "[", "]")
    listed = {}
    for number, text in enumerate(shape.mask_literals(listing).split("\n"), offset + 1):
        match = re.fullmatch(r"\s*\.(\w+),\s*", text)
        if not match:
            if text.strip():
                errors.append(f"{LIST}:{number}: list one feature per line, as .name,")
        elif match[1] in listed:
            errors.append(f"{LIST}:{number}: .{match[1]} listed twice (first at line {listed[match[1]]})")
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
        if declaration and not place and relative != LIST:
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
        if feature in features_described and not path.with_name(f"{place[1]}Descriptor.swift").exists():
            errors.append(f"{relative}:1: put it beside {place[1]}Descriptor.swift")
        if feature not in listed:
            errors.append(f"{relative}:1: list .{feature}, in {LIST}")
        spans = [span(source, rf"\b{label}\s*:", "[", "]") for label in ("allowed", "excluded")]
        allowed = {}
        for (start, end), keyed in zip(spans, (True, False)):
            for key, line in entries(source[start:end], source.count("\n", 0, start), keyed):
                key = value(key, path.parent, hub)
                declared.setdefault(key, []).append(f"{relative}:{line}")
                if keyed:
                    allowed[key] = line
                if keyed and CONFIDENTIAL_LOOKING.search(key):
                    errors.append(f"{relative}:{line}: {NOT_FOR_BACKUP}")
        written, read = ({value(key, path.parent, hub): line for key, line in keys.items()}
                         for keys in live_keys(source, spans))
        # A file that only excludes keys carries no closure.
        for label, live, verb in (("snapshot", written, "writes"), ("apply", read, "reads")):
            if re.search(rf"\b{label}\s*:", code):
                errors.extend(f"{relative}:{line}: {key} is allowed, but {label} never {verb} it"
                              for key, line in allowed.items() if key not in live)
                errors.extend(f"{relative}:{line}: {label} {verb} {key}, which the file does not allow"
                              for key, line in live.items() if key not in allowed)
    errors.extend(f"{LIST}:{line}: .{name} has no {name[:1].upper() + name[1:]}BackupKeys.swift"
                  for name, line in listed.items() if name not in files)
    for key, places in declared.items():
        if len(places) > 1:
            errors.append(f"{places[-1]}: {key} declared twice (first at {places[0]})")
    for name, raw in raw_values.items():
        if raw not in declared:
            errors.append(f"{name} ({raw}): unclassified; state backedUp in its descriptor, or its arm in {FEATURE}")
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
