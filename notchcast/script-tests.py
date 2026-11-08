#!/usr/bin/env python3
"""Run every fork Python and shell script test, including nested folders."""
from pathlib import Path
import subprocess
import sys


tests = sorted(path for pattern in ("*-test.py", "*-test.sh") for path in Path("notchcast").rglob(pattern))
if sys.argv[1:] == ["--list"]:
    print("\n".join(map(str, tests)))
else:
    print(f"Running {len(tests)} script tests", flush=True)
    failed = []
    for path in tests:
        print(f"\n=== {path} ===", flush=True)
        command = "python3" if path.suffix == ".py" else "bash"
        if subprocess.run([command, str(path)]).returncode:
            failed.append(str(path))
    print(f"\nScript tests: {len(tests) - len(failed)} passed, {len(failed)} failed", flush=True)
    if failed:
        print("\n".join(failed), file=sys.stderr)
    sys.exit(bool(failed))
