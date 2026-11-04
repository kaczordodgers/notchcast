#!/usr/bin/env python3
"""Exercise SecItemCopyMatching under the gallery's exact launch profile."""

from pathlib import Path
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="notchcast-keychain-") as directory:
    scratch = Path(directory)
    bundle = scratch / "Probe.app"
    executable = bundle / "Contents/MacOS/probe"
    executable.parent.mkdir(parents=True)
    output = scratch / "shots"
    output.mkdir()
    (scratch / "tmp").mkdir()
    subprocess.run(["xcrun", "swiftc", str(here / "keychain-probe.swift"),
                    "-o", str(executable)], check=True)
    subprocess.run([sys.executable, str(here / "isolate.py"), str(scratch),
                    str(output), str(bundle), "probe"], check=True)
