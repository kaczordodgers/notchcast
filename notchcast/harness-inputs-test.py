#!/usr/bin/env python3
"""Exercise harness selection and compiler inputs through the shipped scripts."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
HIDDEN = "Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift"


class HarnessInputsTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="harness-inputs-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        for folder in ("Tests", "notchcast", "bin", "Tinycast/Features/Example/Model",
                       "Tinycast/Features/Example/Service", str(Path(HIDDEN).parent)):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        for name in ("changed-harnesses.sh", "command-harness-sources.sh", "harness_inputs.py",
                     "test-harnesses.sh", "check-module-harness.py"):
            if (ROOT / "notchcast" / name).exists():
                shutil.copy(ROOT / "notchcast" / name, self.root / "notchcast" / name)
        (self.root / "notchcast/config.env").write_text('CI_SKIP_TESTS=""\n')
        (self.root / "bin/git").write_text(
            '#!/bin/bash\ncase "$1" in\nrev-parse) printf "%s\\n" "$FIXTURE_ROOT" ;;\n'
            'diff) if [[ " $* " == *" -z "* ]]; then printf "%s\\0" "$CHANGED"; '
            'else printf "%s\\n" "$CHANGED"; fi ;;\nesac\n')
        (self.root / "bin/git").chmod(0o755)
        self.env = {**os.environ, "PATH": f"{self.root}/bin:{os.environ['PATH']}",
                    "FIXTURE_ROOT": str(self.root), "GITHUB_ACTIONS": ""}
        self.env.pop("GITHUB_ACTIONS")
        (self.root / "Tinycast/Features/Example/Model/Example.swift").touch()
        (self.root / HIDDEN).touch()
        (self.root / "Tests/nc-Example-conditional-test.swift").write_text(
            '// notchcast-sources: Tinycast/Features/Example/Model/*.swift\n')
        (self.root / "Tests/notchcast-reader-test.swift").write_text(
            '// notchcast-sources: -parse-as-library\n// notchcast-reads: fixtures/*.txt\n')
        (self.root / "Tests/nc-Example-folder-test.swift").touch()

    def selected(self, changed):
        result = subprocess.run(["bash", "notchcast/changed-harnesses.sh", "base", "head"],
                                cwd=self.root, env={**self.env, "CHANGED": changed},
                                text=True, capture_output=True, check=True)
        print(f"{changed} selects {result.stdout.strip().replace(chr(10), ', ')}", flush=True)
        return result.stdout.splitlines()

    def test_conditional_source_selects_consumer(self):
        self.assertIn("nc-Example-conditional-test", self.selected(HIDDEN))

    def test_text_read_selects_consumer_even_after_deletion(self):
        self.assertIn("notchcast-reader-test", self.selected("fixtures/deleted.txt"))

    def test_folder_source_selects_consumer_even_after_deletion(self):
        self.assertIn("nc-Example-folder-test",
                      self.selected("Tinycast/Features/Example/Service/Removed.swift"))

    def test_unrelated_change_does_not_select_consumers(self):
        self.assertEqual(["notchcast-core-test"], self.selected("unrelated.txt"))

    def test_runner_keeps_reads_out_of_compiler_arguments(self):
        result = subprocess.run(["bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                                 'run() { printf "%s\\n" "$*"; }; source notchcast/test-harnesses.sh'],
                                cwd=self.root, env=self.env, text=True, capture_output=True, check=True)
        lines = result.stdout.splitlines()
        conditional = next(line for line in lines if line.startswith("nc-Example-conditional-test "))
        self.assertIn(HIDDEN, conditional)
        self.assertNotIn("fixtures/", result.stdout)
        self.assertIn("notchcast-reader-test -parse-as-library", lines)

    def test_module_check_includes_conditional_sources(self):
        source = "Tinycast/Features/Notchcast/Core/NotchcastFeatureModule.swift"
        (self.root / source).parent.mkdir(parents=True, exist_ok=True)
        (self.root / source).touch()
        catalog = "Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift"
        (self.root / catalog).parent.mkdir(parents=True, exist_ok=True)
        (self.root / catalog).touch()
        (self.root / "Tests/nc-Example-catalog-test.swift").write_text(f"// notchcast-sources: {catalog}\n")
        result = subprocess.run(["python3", "notchcast/check-module-harness.py", "base", "head"],
                                cwd=self.root, env={**self.env, "CHANGED": source},
                                text=True, capture_output=True, check=True)
        self.assertEqual("", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
