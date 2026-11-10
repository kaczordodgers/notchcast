#!/usr/bin/env python3
"""Discover fork script tests, keeping host-integrated checks opt-in."""
import argparse
import os
from pathlib import Path
import subprocess
import sys


RUNTIMES = {".py": ["python3"], ".sh": ["bash"], ".mjs": ["node"],
            ".swift": ["swift", "-swift-version", "6"]}
ALL_ONLY = {
    Path("notchcast/install-app-test.sh"),
    Path("notchcast/gallery/keychain-test.py"),
}
LAND_TEST = Path("notchcast/land-test.sh")
LAND_INPUTS = ["notchcast/land.sh", "notchcast/merge.sh", "notchcast/drift-gates.sh", "notchcast/fork-point.sh",
               str(LAND_TEST)]


def land_inputs_changed():
    # A diff that cannot be read (no base fetched) runs the test rather than skipping it.
    base = os.environ.get("BASE_SHA") or "origin/main"
    try:
        return bool(subprocess.check_output(["git", "diff", "--name-only", f"{base}...HEAD", "--", *LAND_INPUTS],
                                            text=True, stderr=subprocess.DEVNULL).strip())
    except (OSError, subprocess.CalledProcessError):
        return True


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--all", action="store_true", help="include host-integrated tests")
parser.add_argument("--list", action="store_true", help="list selected tests without running them")
args = parser.parse_args()
discovered = sorted(path for suffix in RUNTIMES for path in Path("notchcast").rglob(f"*-test{suffix}"))
tests = [path for path in discovered if args.all or path not in ALL_ONLY]
if not tests:
    sys.exit("script-tests.py: no tests found; run it from the repository root")
opt_in = len(discovered) - len(tests)
if not args.all and LAND_TEST in tests and not land_inputs_changed():
    tests.remove(LAND_TEST)
    print(f"Skipping {LAND_TEST}: the diff does not touch {', '.join(LAND_INPUTS)}", file=sys.stderr, flush=True)
if args.list:
    print("\n".join(map(str, tests)))
else:
    print(f"Running {len(tests)} script tests ({opt_in} opt-in tests excluded)", flush=True)
    failed = []
    for path in tests:
        print(f"\n=== {path} ===", flush=True)
        if subprocess.run([*RUNTIMES[path.suffix], str(path)]).returncode:
            failed.append(str(path))
    print(f"\nScript tests: {len(tests) - len(failed)} passed, {len(failed)} failed", flush=True)
    if failed:
        print("\n".join(failed), file=sys.stderr)
    sys.exit(bool(failed))
