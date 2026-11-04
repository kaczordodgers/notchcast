#!/usr/bin/env python3
"""Warn when a PR adds a *Module.swift that no harness compiles.

Swift 6 region-isolation errors appear only when a file is compiled, not type-checked, so a module file needs a
harness that lists it (a `// notchcast-sources:` header, or the nc-<Folder> harness's {Model,Service} folders).
Only files the PR adds are checked; existing modules are grandfathered. Warns, never fails.
Usage: check-module-harness.py <base-ref> [<head-ref>]
"""
import glob
import pathlib
import subprocess
import sys

base, head = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "HEAD")
added = subprocess.run(["git", "diff", "--name-only", "--diff-filter=A", f"{base}...{head}", "--", "Tinycast/"],
                       capture_output=True, text=True, check=True).stdout.split()
added = [f for f in added if f.endswith("Module.swift")]
compiled = set()
for harness in glob.glob("Tests/*-test.swift"):
    name = pathlib.Path(harness).stem
    headers = [l.split(":", 1)[1].split() for l in open(harness, encoding="utf-8", errors="replace")
               if l.startswith("// notchcast-sources:")]
    if headers:
        for words in headers:
            for word in words:
                compiled.update(glob.glob(word))
    elif name.startswith("nc-"):
        folder = name[3:].split("-")[0]
        compiled.update(glob.glob(f"Tinycast/Features/{folder}/Model/*.swift"))
        compiled.update(glob.glob(f"Tinycast/Features/{folder}/Service/*.swift"))
for f in added:
    if f not in compiled:
        print(f"::warning file={f}::{f} is a new module with no harness compiling it; Swift 6 isolation errors "
              "in it surface only in the Xcode build. Add it to a harness's notchcast-sources line.")
