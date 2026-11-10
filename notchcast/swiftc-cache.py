#!/usr/bin/env python3
"""A swiftc for CI harness steps that restores a cached binary instead of compiling the same thing again.

    <dir>/swiftc -> swiftc-cache.py     first on PATH (ci-tests.sh links it when NOTCHCAST_SWIFTC_CACHE is set)
    swiftc-cache.py finish              drop cache entries this job did not use; print and output the counts

The key is NOTCHCAST_SWIFTC_TOOLCHAIN (compiler version, SDK, OS build), the working directory (Swift embeds
#filePath), every argument except the -o path, and the contents of every argument that is a file. Only a compile
that writes one output from the files it names is cached: an option outside PLAIN (a search path, a second
output, a response file) or a directory argument compiles for real, every time.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys

PLAIN = {"-o", "-swift-version", "-O", "-Onone", "-parse-as-library", "-strict-concurrency=complete", "-target",
         "-warnings-as-errors", "-Xlinker", "-sectcreate", "-lsqlite3"}


def cache_key(toolchain, args, root):
    """None when the compile may read or write something its arguments do not name."""
    digest = hashlib.sha256(f"{toolchain}\0{root}".encode())
    for index, arg in enumerate(args):
        path = Path(root, arg)
        if arg.startswith(("-", "@")) and arg not in PLAIN or path.is_dir():
            return None
        if index and args[index - 1] == "-o":
            continue
        digest.update(b"\0" + arg.encode())
        if path.is_file():
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def shim(args):
    cache = Path(os.environ["NOTCHCAST_SWIFTC_CACHE"])
    compiler = [os.environ["NOTCHCAST_SWIFTC_REAL"], *args]
    key = cache_key(os.environ["NOTCHCAST_SWIFTC_TOOLCHAIN"], args, Path.cwd()) if "-o" in args[:-1] else None
    if key is None:
        return subprocess.run(compiler).returncode
    output = Path(args[args.index("-o") + 1])
    entry = cache / key
    hit = entry.is_file()
    if hit:
        shutil.copyfile(entry, output)
        output.chmod(0o755)
    else:
        status = subprocess.run(compiler).returncode
        if status:
            return status
        partial = cache / f"{key}.{os.getpid()}"
        shutil.copyfile(output, partial)
        partial.replace(entry)
    # One short O_APPEND write per compile, so parallel compiles never interleave.
    with open(f"{cache}.log", "a") as log:
        log.write(f"{'hit' if hit else 'stored'} {key}\n")
    return 0


def finish():
    cache = Path(os.environ["NOTCHCAST_SWIFTC_CACHE"])
    log = Path(f"{cache}.log")
    lines = [line.split() for line in log.read_text().splitlines()] if log.exists() else []
    used = {key for _, key in lines}
    stored = len({key for kind, key in lines if kind == "stored"})
    # Without a log no compile ran here, and pruning would save an empty cache over a full one.
    unused = [entry for entry in cache.iterdir() if entry.name not in used] if used else []
    for entry in unused:
        entry.unlink()
    size = sum(entry.stat().st_size for entry in cache.iterdir()) if cache.is_dir() else 0
    print(f"swiftc cache: {len(used) - stored} restored, {stored} compiled, {len(unused)} unused dropped, "
          f"{size / 1e6:.0f} MB kept")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as out:
            out.write(f"stored={stored}\n")


if __name__ == "__main__":
    if Path(sys.argv[0]).name == "swiftc":
        sys.exit(shim(sys.argv[1:]))
    if sys.argv[1:] != ["finish"]:
        sys.exit(__doc__)
    finish()
