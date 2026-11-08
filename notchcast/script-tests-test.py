#!/usr/bin/env python3
"""Verify script-test lanes, recursive discovery and interpreter dispatch."""
from contextlib import chdir, redirect_stderr, redirect_stdout
import io
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("script-tests.py").resolve()
DEFAULT = ["notchcast/nested/plain-test.py", "notchcast/plain-test.sh",
           "notchcast/generated-retry-test.mjs", "notchcast/gallery/check-pixels-test.swift"]
OPT_IN = ["notchcast/land-test.sh", "notchcast/install-app-test.sh", "notchcast/gallery/keychain-test.py"]


class ScriptTestsTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="script-tests-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        for name in DEFAULT + OPT_IN + ["notchcast/helper.py"]:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()

    def invoke(self, arguments, returncode=0):
        output = io.StringIO()
        with chdir(self.root), patch.object(sys, "argv", [str(SCRIPT), *arguments]), \
                redirect_stdout(output), redirect_stderr(io.StringIO()), patch("subprocess.run") as run:
            run.return_value.returncode = returncode
            try:
                runpy.run_path(str(SCRIPT), run_name="__main__")
                status = 0
            except SystemExit as error:
                status = error.code
        return status, output.getvalue(), [call.args[0] for call in run.call_args_list]

    def test_default_discovers_four_runtimes_without_host_integrated_tests(self):
        status, output, commands = self.invoke(["--list"])
        self.assertEqual(0, status)
        self.assertEqual(sorted(DEFAULT), output.splitlines())
        self.assertEqual([], commands)

    def test_all_lists_every_test_including_opt_in_paths(self):
        status, output, commands = self.invoke(["--all", "--list"])
        self.assertEqual(0, status)
        self.assertEqual(sorted(DEFAULT + OPT_IN), output.splitlines())
        self.assertEqual([], commands)

    def test_execution_uses_each_interpreter(self):
        status, output, commands = self.invoke([])
        self.assertEqual(0, status)
        self.assertIn("4 passed, 0 failed", output)
        self.assertIn("3 opt-in tests excluded", output)
        self.assertEqual(sorted([
            ["python3", DEFAULT[0]], ["bash", DEFAULT[1]], ["node", DEFAULT[2]],
            ["swift", "-swift-version", "6", DEFAULT[3]],
        ]), sorted(commands))

    def test_test_failure_fails_the_lane(self):
        status, output, commands = self.invoke(["--all"], returncode=1)
        self.assertNotEqual(0, status)
        self.assertEqual(7, len(commands))
        self.assertIn("0 passed, 7 failed", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
