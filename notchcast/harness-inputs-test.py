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
        for folder in ("Tests", "Scripts", "notchcast", "bin", "Tinycast/Features/Example/Model",
                       "Tinycast/Features/Example/Service", str(Path(HIDDEN).parent)):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        for name in ("changed-harnesses.sh", "command-harness-sources.sh", "harness_inputs.py",
                     "test-harnesses.sh", "check-module-harness.py"):
            if (ROOT / "notchcast" / name).exists():
                shutil.copy(ROOT / "notchcast" / name, self.root / "notchcast" / name)
        (self.root / "Scripts/run-tests.sh").touch()
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

    def test_upstream_registration_selects_conditional_tabs_consumer(self):
        shutil.copy(ROOT / "Scripts/run-tests.sh", self.root / "Scripts/run-tests.sh")
        (self.root / "Tests/launcher-settings-file-test.swift").touch()
        self.assertIn("launcher-settings-file-test", self.selected(
            "Tinycast/Features/Notchcast/Hidden/NotchcastHidden+Tabs.swift"))

    def test_upstream_queue_gets_only_additional_inputs(self):
        source = "Tinycast/Features/Settings/SettingsTab.swift"
        (self.root / source).parent.mkdir(parents=True, exist_ok=True)
        (self.root / source).touch()
        (self.root / "Scripts/run-tests.sh").write_text(
            'S=Tinycast/Features/Settings\nBASE="$S/SettingsTab.swift"\n'
            'run slow -O launcher-settings-file-test \\\n    $BASE # upstream inputs\n')
        (self.root / "Tests/launcher-settings-file-test.swift").write_text(
            '// notchcast-sources: -framework AppKit\n')
        queue = self.root / "queue"
        queue.write_text(f"0 launcher-settings-file-test -O {source}\n")
        subprocess.run(["bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                        'run() { :; }; source notchcast/test-harnesses.sh'],
                       cwd=self.root, env=self.env, check=True)
        arguments = queue.read_text().split()
        self.assertEqual(1, arguments.count(source))
        self.assertIn("Tinycast/Features/Notchcast/Hidden/NotchcastHidden+Tabs.swift", arguments)
        self.assertEqual(["-framework", "AppKit"], arguments[arguments.index("-framework"):][:2])

    def test_text_read_selects_consumer_even_after_deletion(self):
        self.assertIn("notchcast-reader-test", self.selected("fixtures/deleted.txt"))

    def test_folder_source_selects_consumer_even_after_deletion(self):
        self.assertIn("nc-Example-folder-test",
                      self.selected("Tinycast/Features/Example/Service/Removed.swift"))

    def test_repository_read_headers_select_their_consumers(self):
        cases = {
            "Tinycast/Features/Katana/README.md": ["nc-Katana-core-test"],
            "notchcast/docs/katana.md": ["nc-Katana-core-test"],
            "Tests/Fixtures/todoist-export.json": ["nc-Todo-import-test", "nc-Todo-settings-test"],
            "Tests/fixtures/build-stats-v1.json": ["notchcast-build-stats-test"],
            "Tests/Fixtures/ai-usage/cache-shapes.json": ["notchcast-l5-ai-usage-test"],
            "notchcast/test-archives-fallback.py": ["nc-Archives-fallback-test"],
        }
        for name in {name for names in cases.values() for name in names}:
            shutil.copy(ROOT / "Tests" / f"{name}.swift", self.root / "Tests")
        for changed, names in cases.items():
            with self.subTest(changed=changed):
                selected = self.selected(changed)
                for name in names:
                    self.assertIn(name, selected)

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

    def test_conditional_globs_do_not_duplicate_sources_or_drop_repeated_flags(self):
        source = "Tinycast/Features/Notchcast/Core/NotchcastFeatureModule.swift"
        (self.root / source).parent.mkdir(parents=True, exist_ok=True)
        (self.root / source).touch()
        tab = "Tinycast/Features/Settings/SettingsTab.swift"
        (self.root / tab).parent.mkdir(parents=True, exist_ok=True)
        (self.root / tab).touch()
        (self.root / "Tests/nc-Example-overlap-test.swift").write_text(
            f"// notchcast-sources: -framework AppKit -framework Foundation {source} {tab}\n")
        result = subprocess.run(["bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                                 'run() { printf "%s\\n" "$*"; }; source notchcast/test-harnesses.sh'],
                                cwd=self.root, env=self.env, text=True, capture_output=True, check=True)
        arguments = next(line.split()[1:] for line in result.stdout.splitlines()
                         if line.startswith("nc-Example-overlap-test "))
        self.assertEqual(1, arguments.count(source))
        self.assertEqual(["-framework", "AppKit", "-framework", "Foundation"], arguments[:4])

    def test_runner_batches_conditional_inputs_in_one_bash_invocation(self):
        calls = self.root / "bash-calls"
        (self.root / "bin/bash").write_text(
            '#!/bin/bash\nprintf "call\\n" >> "$BASH_CALLS"\nexec /bin/bash "$@"\n')
        (self.root / "bin/bash").chmod(0o755)
        subprocess.run(["/bin/bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                        'run() { :; }; source notchcast/test-harnesses.sh'],
                       cwd=self.root, env={**self.env, "BASH_CALLS": str(calls)}, check=True)
        self.assertEqual(["call"], calls.read_text().splitlines())

    def assert_runner_refuses_invalid_inputs(self):
        result = subprocess.run(["bash", "-uc", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                                 'run() { printf "registered %s\\n" "$*"; }; '
                                 'source notchcast/test-harnesses.sh; printf "suite passed\\n"'],
                                cwd=self.root, env=self.env, text=True, capture_output=True)
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("::error::", result.stderr)
        self.assertNotIn("suite passed", result.stdout)
        self.assertNotIn("registered", result.stdout)

    def test_bad_header_fails_runner_even_when_source_status_is_ignored(self):
        (self.root / "Tests/nc-Example-broken-test.swift").write_text(
            '// notchcast-sources: -Xcc "-DBROKEN\n')
        self.assert_runner_refuses_invalid_inputs()

    def test_invalid_utf8_fails_runner(self):
        (self.root / "Tests/nc-Example-broken-test.swift").write_bytes(bytes([255]))
        self.assert_runner_refuses_invalid_inputs()

    def test_conditional_helper_failure_fails_runner(self):
        (self.root / "notchcast/command-harness-sources.sh").write_text('false\nprintf "masked\\n"\n')
        self.assert_runner_refuses_invalid_inputs()

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
