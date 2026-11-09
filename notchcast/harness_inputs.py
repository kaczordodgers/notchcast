#!/usr/bin/env python3
"""Resolve fork harness compiler arguments and change-selection dependencies."""
from dataclasses import dataclass
import glob
from pathlib import Path
import re
import shlex
import subprocess
import sys


@dataclass
class HarnessInputs:
    arguments: list[str]
    patterns: list[str]
    reads: list[str]
    has_header: bool
    registered_count: int
    headerless_fork: bool = False


def upstream_registrations() -> dict[str, list[str]]:
    variables = {}
    registrations = {}

    def expand(value):
        return re.sub(r"\$(?:\{(\w+)\}|(\w+))",
                      lambda match: expand(variables[match[1] or match[2]]), value)

    script = Path("Scripts/run-tests.sh").read_text(encoding="utf-8").replace("\\\n", " ")
    for line in script.splitlines():
        assignment = re.fullmatch(r"([A-Z][A-Z0-9_]*)=(.*)", line)
        if assignment:
            variables[assignment[1]] = " ".join(shlex.split(assignment[2], comments=True))
        elif line.startswith("run "):
            tokens = shlex.split(line, comments=True)[1:]
            while tokens[0] in ("slow", "-O", "index"):
                tokens.pop(0)
            name, *arguments = tokens
            registrations[name] = [word for arg in arguments for word in expand(arg).split()]
    return registrations


def kit_lines(name: str) -> list[str]:
    kit = Path("Tests/Kit") / f"{name}.kit"
    if not kit.is_file():
        raise ValueError(f"unknown notchcast-kit '{name}': {kit} does not exist")
    lines = [line.split("#", 1)[0].strip() for line in kit.read_text(encoding="utf-8").splitlines()]
    lines = [line for line in lines if line]
    if not lines:
        raise ValueError(f"notchcast-kit '{name}' is empty: {kit} lists no sources")
    return lines


def read_inputs(path: Path, registered: list[str]) -> HarnessInputs:
    headers = {"sources": [], "reads": []}
    has_header = False
    kits = []
    for line in path.read_text(encoding="utf-8").splitlines():
        for kind in headers:
            prefix = f"// notchcast-{kind}:"
            if line.startswith(prefix):
                headers[kind].extend(shlex.split(line[len(prefix):]))
                has_header |= kind == "sources"
        if line.startswith("// notchcast-kit:"):
            names = shlex.split(line[len("// notchcast-kit:"):])
            if not names:
                raise ValueError(f"{path}: // notchcast-kit: names no kit")
            for name in names:
                kits.append(f"Tests/Kit/{name}.kit")
                headers["sources"].extend(kit_lines(name))
            has_header = True
    sources = headers["sources"]
    if not has_header and path.stem.startswith("nc-"):
        folder = path.stem[3:].split("-", 1)[0]
        sources = [f"Tinycast/Features/{folder}/{part}/*.swift" for part in ("Model", "Service")]
    arguments = [arg for arg in sources if has_header or glob.glob(arg)]
    upstream = [value for arg in registered for value in (sorted(glob.glob(arg)) or [arg])]
    expanded = upstream.copy()
    for arg in arguments:
        for value in sorted(glob.glob(arg)) or [arg]:
            # A kit glob and a plain file line may name one source; compiling it twice redefines its types.
            if not (value in expanded and Path(value).is_file()):
                expanded.append(value)
    return HarnessInputs(expanded, registered + sources + kits, headers["reads"], has_header, len(upstream))


def fork_owned(path: Path) -> bool:
    """True when the harness is absent from the upstream merge base (cannot tell without the ref)."""
    base = subprocess.run(["git", "merge-base", "HEAD", "refs/remotes/upstream/main"],
                          text=True, capture_output=True)
    if base.returncode != 0:
        return False
    return subprocess.run(["git", "cat-file", "-e", f"{base.stdout.strip()}:{path}"],
                          capture_output=True).returncode != 0


def harnesses():
    registrations = upstream_registrations()
    entries = [(path, read_inputs(path, registrations.get(path.stem, [])))
               for path in sorted(Path("Tests").glob("*-test.swift"))]
    script = 'set -ef\naugment() {\nlocal name=$1; shift\n' \
             'source notchcast/command-harness-sources.sh\n' \
             'printf "%s\\0" "$name" "$@"\nprintf "\\0"\n}\n'
    script += "\n".join(shlex.join(["augment", path.stem, *inputs.arguments]) for path, inputs in entries)
    result = subprocess.run(["bash"], input=script, text=True, stdout=subprocess.PIPE, check=True)
    batches = result.stdout.split("\0\0")[:-1]
    for (path, inputs), batch in zip(entries, batches, strict=True):
        name, *augmented = batch.split("\0")
        if name != path.stem:
            raise ValueError(f"Unexpected harness input result: {name}")
        compiled = inputs.arguments.copy()
        for arg in augmented[len(inputs.arguments):]:
            for value in sorted(glob.glob(arg)) or [arg]:
                if value not in compiled:
                    compiled.append(value)
        inputs.patterns = list(dict.fromkeys(arg for arg in [*inputs.patterns, *augmented]
                                            if not arg.startswith("-")))
        inputs.arguments = compiled
        inputs.headerless_fork = not (inputs.has_header or inputs.arguments or inputs.reads
                                      or path.stem.startswith(("nc-", "notchcast-"))) and fork_owned(path)
        if inputs.has_header or inputs.arguments or inputs.reads or inputs.headerless_fork \
                or path.stem.startswith(("nc-", "notchcast-")):
            yield path, inputs


if __name__ == "__main__":
    try:
        entries = list(harnesses())
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
    for path, inputs in entries:
        if inputs.has_header or inputs.headerless_fork or path.stem.startswith(("nc-", "notchcast-")):
            additions = inputs.arguments[inputs.registered_count:]
            print("\t".join([str(path), str(int(inputs.has_header)), " ".join(additions)]))
