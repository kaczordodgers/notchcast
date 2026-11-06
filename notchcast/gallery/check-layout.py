#!/usr/bin/env python3
"""Check measured accessibility frames without correcting or rounding the source data."""

import json
import math
from pathlib import Path
import sys


def rect(value):
    values = tuple(float(value[key]) for key in ("x", "y", "width", "height"))
    if not all(math.isfinite(number) for number in values) or min(values[2:]) < 0:
        raise ValueError("invalid rectangle")
    return values


def inside(frame, surface):
    x, y, width, height = frame
    sx, sy, sw, sh = surface
    return x >= sx - 0.01 and y >= sy - 0.01 and x + width <= sx + sw + 0.01 and y + height <= sy + sh + 0.01


def overlaps(first, second):
    x, y, width, height = first
    sx, sy, sw, sh = second
    return min(x + width, sx + sw) > max(x, sx) + 0.01 and min(y + height, sy + sh) > max(y, sy) + 0.01


def problems(layout):
    canvas = rect(layout["canvas"])
    surface = rect(layout["surface"])
    found = []
    if not inside(surface, canvas):
        found.append("surface outside canvas")
    elements = layout["elements"]
    measured = 0
    notch = layout.get("hardwareNotch")
    closed_mba = layout["page"].startswith("island-closed-") and layout["page"].endswith("-mba")
    containers = {"AXGroup", "AXScrollArea", "AXList", "AXLayoutArea", "AXUnknown"}
    for index, element in enumerate(elements):
        frame = rect(element["frame"])
        name = element.get("label") or f'{element["role"]}[{index}]'
        if index == 0 and element["role"] == "AXGroup" and not element.get("label") and frame == canvas:
            continue
        measured += 1
        if not inside(frame, surface):
            found.append(f"{name}: outside surface")
        x, y, width, height = frame
        if any(abs(edge * 2 - round(edge * 2)) > 0.01 for edge in (x, y, x + width, y + height)):
            found.append(f"{name}: edge between 2x pixels")
        if closed_mba and notch and element["role"] not in containers and overlaps(frame, rect(notch)):
            found.append(f"{name}: under hardware notch")
    if measured == 0:
        found.append("accessibility tree has no measured elements")
    return found


def check(directory):
    manifest = directory / "manifest.txt"
    if not manifest.is_file():
        print("FAIL manifest.txt: missing")
        return 1
    pages = manifest.read_text().splitlines()
    failed = 0
    incomplete = 0
    if not pages or len(pages) != len(set(pages)):
        print("FAIL manifest.txt: empty or duplicate pages")
        return 1
    for page in pages:
        path = directory / (Path(page).stem + "-layout.json")
        try:
            if Path(page).name != page or not (directory / page).is_file():
                raise ValueError("missing PNG or invalid page name")
            layout = json.loads(path.read_text())
            incomplete += int(not layout.get("accessibilityComplete", True))
            if layout["page"] != Path(page).stem or layout["scale"] != 2:
                raise ValueError("page or scale mismatch")
            issues = problems(layout)
        except (OSError, ValueError, KeyError, TypeError) as error:
            issues = [str(error)]
        if issues:
            failed += 1
            print(f"FAIL {path.name}")
            for issue in issues:
                print(f"  - {issue}")
        else:
            print(f"PASS {path.name}: {len(layout['elements'])} elements")
    print(f"layout: {len(pages) - failed} PASS, {failed} FAIL, {len(pages)} pages; {incomplete} incomplete AX exports")
    return int(failed > 0)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: check-layout.py <shots-directory>")
    sys.exit(check(Path(sys.argv[1])))
