#!/usr/bin/env python3
"""swiftc-cache.py behind a stand-in compiler: what is restored, what compiles again, what is never cached."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOL = Path(__file__).resolve().parent / "swiftc-cache.py"
# Writes its arguments' file contents to the -o path and counts its runs; `fail.swift` does not compile.
COMPILER = """#!/bin/bash
echo run >> "$CALLS"
out=
for arg in "$@"; do
    [ "$previous" = -o ] && out=$arg
    [ "$arg" = fail.swift ] && exit 3
    previous=$arg
done
[ -z "$out" ] || cat -- *.swift > "$out"
"""


class SwiftcCacheTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        (self.root / "work").mkdir()
        (self.root / "cache").mkdir()
        (self.root / "shim").mkdir()
        (self.root / "shim/swiftc").symlink_to(TOOL)
        compiler = self.root / "real-swiftc"
        compiler.write_text(COMPILER)
        compiler.chmod(0o755)
        (self.root / "work/a.swift").write_text("a\n")
        self.env = {**os.environ, "CALLS": str(self.root / "calls"), "NOTCHCAST_SWIFTC_REAL": str(compiler),
                    "NOTCHCAST_SWIFTC_CACHE": str(self.root / "cache"), "NOTCHCAST_SWIFTC_TOOLCHAIN": "swift 6"}

    def swiftc(self, *args):
        return subprocess.run([str(self.root / "shim/swiftc"), *args], cwd=self.root / "work", env=self.env).returncode

    def calls(self):
        calls = self.root / "calls"
        return len(calls.read_text().splitlines()) if calls.exists() else 0

    def finish(self):
        return subprocess.run([sys.executable, str(TOOL), "finish"], env=self.env, text=True, capture_output=True,
                              check=True).stdout

    def test_same_compile_is_restored_not_compiled(self):
        self.assertEqual(self.swiftc("-swift-version", "6", "a.swift", "-o", "out"), 0)
        (self.root / "work/out").unlink()
        self.assertEqual(self.swiftc("-swift-version", "6", "a.swift", "-o", "elsewhere"), 0)
        self.assertEqual(self.calls(), 1)
        restored = self.root / "work/elsewhere"
        self.assertEqual(restored.read_text(), "a\n")
        self.assertTrue(os.access(restored, os.X_OK))

    def test_any_changed_input_compiles_again(self):
        self.swiftc("-Onone", "a.swift", "-o", "out")
        (self.root / "work/a.swift").write_text("changed\n")
        self.swiftc("-Onone", "a.swift", "-o", "out")
        self.assertEqual((self.root / "work/out").read_text(), "changed\n")
        self.swiftc("-O", "a.swift", "-o", "out")
        self.env["NOTCHCAST_SWIFTC_TOOLCHAIN"] = "swift 7"
        self.swiftc("-O", "a.swift", "-o", "out")
        self.assertEqual(self.calls(), 4)

    def test_failed_compile_is_not_cached(self):
        (self.root / "work/fail.swift").write_text("broken\n")
        self.assertEqual(self.swiftc("fail.swift", "-o", "out"), 3)
        self.assertEqual(self.swiftc("fail.swift", "-o", "out"), 3)
        self.assertEqual(self.calls(), 2)
        self.assertEqual(list((self.root / "cache").iterdir()), [])

    def test_inputs_the_arguments_do_not_name_are_never_cached(self):
        (self.root / "work/headers").mkdir()
        for args in (["-I", "headers", "a.swift", "-o", "out"], ["-emit-module", "a.swift", "-o", "out"],
                     ["headers", "a.swift", "-o", "out"], ["@files.resp", "-o", "out"], ["a.swift"]):
            before = self.calls()
            self.swiftc(*args)
            self.swiftc(*args)
            self.assertEqual(self.calls(), before + 2, args)
        self.assertEqual(list((self.root / "cache").iterdir()), [])

    def test_finish_keeps_what_this_job_used(self):
        self.swiftc("a.swift", "-o", "out")
        self.assertIn("0 restored, 1 compiled, 0 unused dropped", self.finish())
        (self.root / "cache.log").unlink()
        (self.root / "cache/stale").write_text("left by an older tree\n")
        self.assertIn("0 restored, 0 compiled, 0 unused dropped", self.finish())
        self.swiftc("a.swift", "-o", "out")
        output = self.root / "output"
        self.env["GITHUB_OUTPUT"] = str(output)
        self.assertIn("1 restored, 0 compiled, 1 unused dropped", self.finish())
        self.assertEqual(output.read_text(), "stored=0\n")
        self.assertEqual(len(list((self.root / "cache").iterdir())), 1)


if __name__ == "__main__":
    unittest.main()
