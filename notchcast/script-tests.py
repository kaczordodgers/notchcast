#!/usr/bin/env python3
"""Discover fork script tests, keeping slow and host-integrated checks opt-in."""
import argparse
from pathlib import Path
import subprocess
import sys


RUNTIMES = {".py": ["python3"], ".sh": ["bash"], ".mjs": ["node"],
            ".swift": ["swift", "-swift-version", "6"]}
ALL_ONLY = {
    Path("notchcast/land-test.sh"),
    Path("notchcast/install-app-test.sh"),
    Path("notchcast/gallery/keychain-test.py"),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--all", action="store_true", help="include slow and host-integrated tests")
parser.add_argument("--list", action="store_true", help="list selected tests without running them")
args = parser.parse_args()
discovered = sorted(path for suffix in RUNTIMES for path in Path("notchcast").rglob(f"*-test{suffix}"))
tests = [path for path in discovered if args.all or path not in ALL_ONLY]
if not tests:
    sys.exit("script-tests.py: no tests found; run it from the repository root")
if args.list:
    print("\n".join(map(str, tests)))
else:
    print(f"Running {len(tests)} script tests ({len(discovered) - len(tests)} opt-in tests excluded)", flush=True)
    failed = []
    for path in tests:
        print(f"\n=== {path} ===", flush=True)
        if subprocess.run([*RUNTIMES[path.suffix], str(path)]).returncode:
            failed.append(str(path))
    print(f"\nScript tests: {len(tests) - len(failed)} passed, {len(failed)} failed", flush=True)
    if failed:
        print("\n".join(failed), file=sys.stderr)
    sys.exit(bool(failed))
