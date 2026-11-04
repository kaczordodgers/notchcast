#!/usr/bin/env python3
"""Require a catalog command or a reviewed, declared user path for every switch."""

import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = Path("Tinycast/Features/Notchcast/Core/NotchcastFeature.swift")
CATALOG = Path("Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift")
ALLOWLIST = Path("notchcast/switch-path-allowlist-2026-11-04.json")
PATHS = Path("notchcast/switch-paths.json")
spec = importlib.util.spec_from_file_location("shape", Path(__file__).with_name("check-feature-shape.py"))
shape = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shape)


def command_paths(root):
    catalog = shape.mask_literals((root / CATALOG).read_text())
    entries = set(re.findall(r"\b(\w+)\.(\w+)(?:\[\d+\])?\s*,", catalog))
    found = set()
    for path in (root / "Tinycast").rglob("*.swift"):
        code = shape.mask_literals(path.read_text())
        owners = [m for m in re.finditer(r"\b(?:extension|struct|enum|class)\s+(\w+)[^{]*\{", code)
                  if code.count("{", 0, m.start()) == code.count("}", 0, m.start())]
        declarations = list(re.finditer(r"\b(?:static\s+)?(?:let|var)\s+(\w+)\b", code))
        for index, declaration in enumerate(declarations):
            owner = next((m[1] for m in reversed(owners) if m.start() < declaration.start()), None)
            if (owner, declaration[1]) not in entries:
                continue
            start = code.find("NotchcastCommand(", declaration.end())
            next_declaration = declarations[index + 1].start() if index + 1 < len(declarations) else len(code)
            if start < 0 or start > next_declaration:
                continue
            depth = 1
            end = start + len("NotchcastCommand(")
            begin = end
            while depth and end < len(code):
                depth += (code[end] == "(") - (code[end] == ")")
                end += 1
            body = code[begin:end]
            body = body.split("run:", 1)[0]
            found.update(re.findall(r"\bfeature\s*:\s*\.(\w+)", body))
            if "isEnabled:" in body:
                gate = body.split("isEnabled:", 1)[1]
                found.update(re.findall(r"\b(?:isOn|isEnabled)\s*\(\s*\.(\w+)\s*\)", gate))
    return found


def check(root):
    code = shape.mask_literals((root / CORE).read_text())
    enum = code.split("enum NotchcastFeature", 1)[1].split("}", 1)[0]
    features = set(re.findall(r"^\s*case\s+(\w+)", enum, re.M))
    if not features:
        return ["switch paths: no NotchcastFeature cases found"]
    commands = command_paths(root) & features
    allowed = json.loads((root / ALLOWLIST).read_text())
    declared = json.loads((root / PATHS).read_text())
    errors = []
    for label, records in (("allowlist", allowed), ("declared paths", declared)):
        for name, reason in records.items():
            if name not in features:
                errors.append(f"{name}: remove unknown switch from {label}")
            if not isinstance(reason, str) or not reason.strip():
                errors.append(f"{name}: {label} requires a plain reason")
    for name in sorted(features):
        has_path = name in commands or name in declared
        if name in allowed and has_path:
            errors.append(f"{name}: remove from allowlist; user path now exists")
        elif name not in allowed and not has_path:
            errors.append(f"{name}: no user path; add a gated catalog command or declare a reason")
    return errors


def main():
    root = Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT
    try:
        errors = check(root)
    except (OSError, ValueError, IndexError) as error:
        errors = [f"switch paths: {error}"]
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("PASS: every switch has a user path or a dated exception")
    return 0


if __name__ == "__main__":
    sys.exit(main())
