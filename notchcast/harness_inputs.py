#!/usr/bin/env python3
"""Resolve fork harness compiler arguments and change-selection dependencies."""
from dataclasses import dataclass
import glob
from pathlib import Path
import shlex
import subprocess
import sys


@dataclass
class HarnessInputs:
    arguments: list[str]
    patterns: list[str]
    reads: list[str]
    has_header: bool


def resolve(path: Path) -> HarnessInputs:
    headers = {"sources": [], "reads": []}
    has_header = False
    for line in path.read_text(encoding="utf-8").splitlines():
        for kind in headers:
            prefix = f"// notchcast-{kind}:"
            if line.startswith(prefix):
                headers[kind].extend(shlex.split(line[len(prefix):]))
                has_header |= kind == "sources"
    sources = headers["sources"]
    if not has_header and path.stem.startswith("nc-"):
        folder = path.stem[3:].split("-", 1)[0]
        sources = [f"Tinycast/Features/{folder}/{part}/*.swift" for part in ("Model", "Service")]
    arguments = [arg for arg in sources if has_header or glob.glob(arg)]
    expanded = [value for arg in arguments for value in (sorted(glob.glob(arg)) or [arg])]
    result = subprocess.check_output(
        ["bash", "-c", 'name=$1; shift; set -f; source notchcast/command-harness-sources.sh; '
         'printf "%s\\0" "$@"', "harness-sources", path.stem, *expanded])
    augmented = [arg for arg in result.decode().split("\0") if arg]
    compiled = expanded.copy()
    for arg in augmented[len(expanded):]:
        for value in sorted(glob.glob(arg)) or [arg]:
            if value not in compiled:
                compiled.append(value)
    patterns = [arg for arg in [*sources, *augmented] if not arg.startswith("-")]
    return HarnessInputs(compiled, list(dict.fromkeys(patterns)),
                         headers["reads"], has_header)


def harnesses():
    for path in sorted(Path("Tests").glob("*-test.swift")):
        inputs = resolve(path)
        if inputs.has_header or inputs.arguments or inputs.reads or path.stem.startswith(("nc-", "notchcast-")):
            yield path, inputs


if __name__ == "__main__":
    for path, inputs in harnesses():
        if inputs.has_header or path.stem.startswith(("nc-", "notchcast-")):
            print("\t".join([str(path), str(int(inputs.has_header)), " ".join(inputs.arguments)]))
