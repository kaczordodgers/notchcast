#!/usr/bin/env python3
"""Refuse island and page values that bypass the island kit.

Island and page views take every size, colour, type and duration from the kit
(`Tinycast/Features/Notchcast/Island/NotchcastTheme.swift` with IslandGeometry, IslandMotion and
IslandSilhouette) or from Tinycast's `Theme`, never from a literal. Findings:
  literal  a number other than 0 and 1 inside a layout or style call (padding, frame, spacing, cornerRadius,
           offset, opacity, shadow, font size, animation duration, ...); a token halved or doubled (`/ 2`, `* 2`)
           is derived, not invented, and passes;
  colour   a raw colour (`Color(red:`, `.white`, `.black`, `.gray`, `Color.white.opacity`, `NSColor.<colour>`);
  font     a fixed `.system(size:` / `NSFont.systemFont(ofSize:` outside NotchcastTheme.swift.
A line ending in `// kit: ok <why>` passes. Files listed in the baseline keep at most their recorded count per rule
(other workers' files, until they fix them); any finding beyond it fails.
Usage: check-kit.py [--root <tree>] [--baseline <json>] [--no-baseline]
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "notchcast/check-kit-baseline.json"
SCANNED = ["Tinycast/Features/Notchcast/Island", "Tinycast/Features/Notchcast/Pages"]
SCANNED_GLOBS = ["Tinycast/Features/*/Island*", "Tinycast/Features/Island*/UI"]
KIT = {"NotchcastTheme.swift", "IslandGeometry.swift", "IslandMotion.swift", "IslandSilhouette.swift"}
FONT_KIT = "NotchcastTheme.swift"

CALLS = ("padding", "frame", "offset", "opacity", "shadow", "cornerRadius", "blur", "position", "scaleEffect",
         "font", "animation", "delay", "speed", "lineSpacing", "kerning", "tracking", "border", "contentMargins",
         "safeAreaPadding")
CONSTRUCTORS = ("CGSize", "EdgeInsets", "RoundedRectangle", "Circle", "Capsule", "UnevenRoundedRectangle")
LABELS = ("spacing", "cornerRadius", "radius", "lineWidth", "duration", "size", "ofSize", "response",
          "dampingFraction", "blendDuration", "bounce", "minLength", "delay")
CALL = re.compile(r"\.(%s)\s*\(|\b(%s)\s*\(" % ("|".join(CALLS), "|".join(CONSTRUCTORS)))
LABEL = re.compile(r"\b(%s)\s*:" % "|".join(LABELS))
NUMBER = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])")
COLOURS = r"white|black|gray|grey|red|green|blue|orange|yellow|pink|purple|brown|cyan|mint|teal|indigo"
RAW_COLOUR = re.compile(
    r"\bColor\s*\(\s*(?:red|white|hue|\.sRGB|\.displayP3)\b"
    r"|\bColor\s*\.\s*(?:%s)\b" % COLOURS
    + r"|(?<![\w.)\]])\.(?:%s)\b" % COLOURS
    + r"|\bNSColor\s*\.\s*(?!clear\b)[a-z]\w*"
    r"|\b(?:NSColor|CGColor)\s*\(")
FIXED_FONT = re.compile(r"\.system\s*\(\s*size\s*:|\bNSFont\s*\.\s*(?:monospacedDigitS|s)ystemFont\s*\(\s*ofSize")
WAIVER = re.compile(r"//\s*kit:\s*ok\s+\S")


def mask(source):
    """Blank comments and string contents, keeping every line in place."""
    pattern = r'//[^\n]*|/\*.*?\*/|""".*?"""|"(?:\\.|[^"\\\n])*"'
    return re.sub(pattern, lambda match: re.sub(r"[^\n]", " ", match[0]), source, flags=re.S)


def closing(code, start):
    """Index of the parenthesis closing the one before `start`, or the end of the code."""
    depth = 1
    for index in range(start, len(code)):
        if code[index] in "([{":
            depth += 1
        elif code[index] in ")]}":
            depth -= 1
            if depth == 0:
                return index
    return len(code)


def argument_end(code, start):
    """End of a labelled argument: the next comma or closing bracket at its own depth."""
    depth = 0
    for index in range(start, len(code)):
        if code[index] in "([{":
            depth += 1
        elif code[index] in ")]}":
            if depth == 0:
                return index
            depth -= 1
        elif code[index] in ",\n" and depth == 0:
            return index
    return len(code)


def derived(code, start, end):
    """A 2 that halves or doubles a token is derived from it."""
    if code[start:end] not in ("2", "2.0"):
        return False
    before = code[:start].rstrip()
    after = code[end:].lstrip()
    return before.endswith(("/", "*")) or after.startswith("*")


def literal_spans(code):
    spans = []
    for match in CALL.finditer(code):
        spans.append((match.end(), closing(code, match.end())))
    for match in LABEL.finditer(code):
        spans.append((match.end(), argument_end(code, match.end())))
    return spans


def findings(path, text):
    code = mask(text)
    lines = text.split("\n")
    line_of = lambda offset: code.count("\n", 0, offset) + 1
    found = set()
    name = Path(path).name
    if name not in KIT:
        for start, end in literal_spans(code):
            for number in NUMBER.finditer(code, start, end):
                value = float(number[1])
                if value in (0, 1) or derived(code, number.start(), number.end()):
                    continue
                found.add((line_of(number.start()), "literal", number[1]))
        for match in RAW_COLOUR.finditer(code):
            found.add((line_of(match.start()), "colour", match[0].strip()))
    if name != FONT_KIT:
        for match in FIXED_FONT.finditer(code):
            found.add((line_of(match.start()), "font", match[0].strip()))
    return sorted(item for item in found if not WAIVER.search(lines[item[0] - 1]))


def scanned_files(root):
    folders = [root / folder for folder in SCANNED]
    for pattern in SCANNED_GLOBS:
        folders += [path for path in root.glob(pattern) if path.is_dir()]
    files = set()
    for folder in folders:
        files.update(folder.rglob("*.swift") if folder.is_dir() else [])
    return sorted(files)


def check(root, baseline):
    total = {}
    for path in scanned_files(root):
        relative = path.relative_to(root).as_posix()
        for line, rule, value in findings(relative, path.read_text(encoding="utf-8")):
            total.setdefault(relative, []).append((line, rule, value))
    failures = 0
    for relative, items in sorted(total.items()):
        allowed = baseline.get(relative, {})
        counts = {}
        for _, rule, _ in items:
            counts[rule] = counts.get(rule, 0) + 1
        over = {rule for rule, count in counts.items() if count > allowed.get(rule, 0)}
        for line, rule, value in items:
            state = "FAIL" if rule in over else "known"
            failures += state == "FAIL"
            print(f"{relative}:{line}: {state} {rule}: {value}")
    for relative, rules in sorted(baseline.items()):
        for rule, count in sorted(rules.items()):
            have = sum(1 for _, found_rule, _ in total.get(relative, []) if found_rule == rule)
            if have < count:
                print(f"{relative}: baseline {rule} {count} > {have} found; lower it in {BASELINE.name}")
    files = len(total)
    if failures:
        print(f"FAIL check-kit: {failures} findings outside the island kit")
        return 1
    print(f"PASS check-kit: no new findings ({sum(len(v) for v in total.values())} known in {files} files)")
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--baseline", type=Path, default=BASELINE)
    parser.add_argument("--no-baseline", action="store_true")
    args = parser.parse_args(argv)
    baseline = {} if args.no_baseline or not args.baseline.exists() else json.loads(args.baseline.read_text())
    return check(args.root.resolve(), baseline)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
