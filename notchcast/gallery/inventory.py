#!/usr/bin/env python3
"""Inventory UI declarations from source; coverage comes only from the run's registry."""

import collections
import json
from pathlib import Path
import re
import sys

DECLARATION = re.compile(
    r"\b(?:struct|class)\s+(\w+)(?:\s*<[^{}]*?>)?\s*:\s*([^{}]+)\{", re.MULTILINE
)
UI_BASE = re.compile(r"\b(?:View|NSViewRepresentable|NSViewControllerRepresentable|NS\w*(?:View|Window|Panel|Control|Field|Button)|"
                     r"NSHostingController|AVPlayerView|PDFView|WKWebView)\b")


def declarations(source):
    source = re.sub(r"/\*.*?\*/|//[^\n]*", lambda match: "\n" * match[0].count("\n"), source, flags=re.DOTALL)
    return [(match[1], source[:match.start()].count("\n") + 1, match[2].strip())
            for match in DECLARATION.finditer(source)]


def generate(root, output):
    coverage = json.loads((output / "coverage.json").read_text())
    manifest = {Path(name).stem for name in (output / "manifest.txt").read_text().splitlines()}
    mapping = collections.defaultdict(set)
    for page in coverage:
        if page["page"] not in manifest:
            raise ValueError("coverage references a page absent from manifest: " + page["page"])
        for name in page["types"]:
            mapping[name].add(page["page"])
    detail = (root / "Tinycast/Features/Settings/SettingsDetailView.swift").read_text()
    tabs = dict(re.findall(r"case\s+\.(\w+):\s*(\w+)\(\)", detail))
    slugs = dict(re.findall(r'case\s+\.(\w+):\s*"([a-z-]+)"',
                           (root / "Tinycast/Features/Settings/SettingsTab.swift").read_text()))
    for tab, name in tabs.items():
        for page in manifest:
            if page in {f"settings-{slugs.get(tab, tab)}-dark", f"settings-{slugs.get(tab, tab)}-light"}:
                mapping[name].add(page)
    candidates = []
    for path in sorted((root / "Tinycast").rglob("*.swift")):
        relative = path.relative_to(root).as_posix()
        for name, line, bases in declarations(path.read_text()):
            candidates.append((relative, name, line, bases))
    ui_types = {name for _, name, _, bases in candidates if UI_BASE.search(bases)}
    while True:
        inherited = {name for _, name, _, bases in candidates if set(re.findall(r"\w+", bases)) & ui_types}
        if inherited <= ui_types:
            break
        ui_types |= inherited
    records = []
    for relative, name, line, bases in candidates:
        if name not in ui_types:
            continue
        area = relative.split("/")[2] if relative.startswith("Tinycast/Features/") else relative.split("/")[1]
        pages = sorted(mapping[name])
        if pages:
            reason = "Registered view; coverage describes these states only, not every conditional branch."
        elif "MenuBar" in name:
            reason = "Excluded: menu bar item and menu."
        elif "/Gallery/" in relative:
            reason = "Gallery harness composition; not a product surface."
        else:
            reason = f"Gap: {area} needs a sample-state registry or explicit child-view coverage."
        records.append({"type": name, "path": relative, "line": line, "area": area,
                        "pages": pages, "reason": reason})
    incomplete = []
    for page in sorted(manifest):
        layout = json.loads((output / (page + "-layout.json")).read_text())
        if not layout.get("accessibilityComplete", False):
            incomplete.append({"page": page, "reason": layout.get("accessibilityGap", "AX coverage not verified")})
    payload = {"schema": 1, "pages": len(manifest), "views": records, "incomplete_exports": incomplete}
    (output / "inventory.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    lines = ["# Gallery inventory", "", f"{len(manifest)} pages; {len(records)} source UI declarations.", "",
             "Page membership records a captured state, not exhaustive state coverage.", "",
             "## Remaining gaps by area", "", "| Area | Unregistered views |", "| --- | ---: |"]
    gaps = collections.Counter(record["area"] for record in records if record["reason"].startswith("Gap:"))
    lines += [f"| {area} | {count} |" for area, count in sorted(gaps.items())]
    lines += ["", "## Incomplete accessibility exports", "", "| Page | Known gap |", "| --- | --- |"]
    lines += [f"| {item['page']} | {item['reason']} |" for item in incomplete]
    lines += ["", "## Every source view", "", "| Type | Source | Pages or reason |", "| --- | --- | --- |"]
    for record in records:
        pages = ", ".join(record["pages"]) or "none — " + record["reason"]
        lines.append(f"| {record['type']} | {record['path']}:{record['line']} | {pages} |")
    (output / "inventory.md").write_text("\n".join(lines) + "\n")
    print(f"inventory: {len(records)} views, {sum(bool(record['pages']) for record in records)} registered, "
          f"{sum(gaps.values())} gaps in {len(gaps)} areas")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: inventory.py <shots-directory>")
    generate(Path(__file__).resolve().parents[2], Path(sys.argv[1]))
