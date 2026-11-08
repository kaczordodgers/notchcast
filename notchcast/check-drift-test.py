#!/usr/bin/env python3
"""Permanent planted violations for each drift gate, using the real CLI and jscpd."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / 'notchcast/check-drift.py'
SPEC = importlib.util.spec_from_file_location('drift', CHECK)
DRIFT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DRIFT)
TODO = 'Tinycast/Features/Todo/DriftProbe.swift'
BATTERY = 'Tinycast/Features/Battery/Store/BatteryModule.swift'
CLEAN = 'Tinycast/Features/Clean/Service/CleanService.swift'


def write(root, path, text):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


class Gates(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix='drift-fixtures.')
        cls.seed = Path(cls.scratch.name) / 'seed'
        cls.seed.mkdir()
        git(cls.seed, 'init', '-q')
        git(cls.seed, 'config', 'user.name', 'Fixture')
        git(cls.seed, 'config', 'user.email', 'fixture@example.com')
        write(cls.seed, 'Tinycast/Features/Launcher/Upstream.swift', 'struct Upstream {}\n')
        git(cls.seed, 'add', '.')
        git(cls.seed, 'commit', '-qm', 'Upstream fixture')
        cls.upstream = git(cls.seed, 'rev-parse', 'HEAD')
        write(cls.seed, 'notchcast/config.env', (ROOT / 'notchcast/config.env').read_text())
        write(cls.seed, 'Tinycast/Features/Katana/KatanaPresetImporter.swift', 'struct KatanaPresetImporter {}\n')
        write(cls.seed, 'Tinycast/Features/Todo/Existing.swift', 'struct TodoExisting {}\n')
        write(cls.seed, 'Tinycast/Features/Treadmill/Existing.swift', 'struct TreadmillExisting {}\n')
        write(cls.seed, BATTERY, (ROOT / BATTERY).read_text())
        write(cls.seed, CLEAN, (ROOT / CLEAN).read_text())
        git(cls.seed, 'add', '.')
        git(cls.seed, 'commit', '-qm', 'Fork fixture')
        result = subprocess.run([sys.executable, str(CHECK), '--root', str(cls.seed), '--upstream', cls.upstream,
                                 '--write-baseline'], capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        git(cls.seed, 'add', '.')
        git(cls.seed, 'commit', '-qm', 'Baseline fixture')

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='drift-case.')
        self.root = Path(self.work.name) / 'tree'
        shutil.copytree(self.seed, self.root)
        self.addCleanup(self.work.cleanup)

    def run_check(self, gate='1,2,3,4', *extra, env=None):
        return subprocess.run([sys.executable, str(CHECK), '--root', str(self.root), '--upstream', self.upstream,
                               '--gates', gate, *extra], capture_output=True, text=True, env=env)

    def red(self, gate, marker):
        result = self.run_check(gate)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(marker, result.stdout + result.stderr)
        print(f'RED gate {gate}: {self._testMethodName} ({marker})')

    def baseline(self):
        return json.loads((self.root / 'notchcast/drift-baseline.json').read_text())

    def save_baseline(self, baseline):
        write(self.root, 'notchcast/drift-baseline.json', json.dumps(baseline, indent=2) + '\n')

    def test_clean_fixture(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_feature_boundary_probe(self):
        write(self.root, TODO, 'let importedPreset = KatanaPresetImporter()\n')
        self.red('1', 'Features/Todo -> Features/Katana')

    def test_core_lookup_probe(self):
        write(self.root, TODO, 'let importedCore = NotchcastCore.todo\n')
        self.red('1', 'core-lookups: ' + TODO)

    def test_file_in_upstream_folder(self):
        write(self.root, 'Tinycast/Features/Launcher/DriftProbe.swift', 'struct DriftProbe {}\n')
        self.red('1', 'upstream-folders:')

    def test_boundary_waiver(self):
        write(self.root, TODO, 'let importedPreset = KatanaPresetImporter() // drift: keep fixture exception\n')
        result = self.run_check('1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_comments_and_strings_do_not_cross_boundaries(self):
        write(self.root, TODO, '// KatanaPresetImporter NotchcastCore.todo\nlet prose = "NotchcastCore.todo"\n')
        self.assertEqual(self.run_check('1').returncode, 0)

    def test_battery_copy_over_400(self):
        write(self.root, 'Tinycast/Features/Todo/DriftBig.swift', (ROOT / BATTERY).read_text())
        self.red('2', 'file-size: Tinycast/Features/Todo/DriftBig.swift: 454 > 0')

    def test_harness_over_600(self):
        write(self.root, 'Tests/drift-test.swift', '\n' * 601)
        self.red('2', '601 > 0')

    def test_generated_file_exempt(self):
        write(self.root, 'Tinycast/Features/Todo/Drift.generated.swift', '\n' * 700)
        self.assertEqual(self.run_check('2').returncode, 0)

    def test_harness_600_allowed(self):
        write(self.root, 'Tests/drift-test.swift', '\n' * 600)
        self.assertEqual(self.run_check('2').returncode, 0)

    def test_file_size_waiver(self):
        write(self.root, 'Tinycast/Features/Todo/DriftBig.swift', '\n' * 401 + '// drift: keep fixture table\n')
        self.assertEqual(self.run_check('2').returncode, 0)

    def test_dead_probe_and_twin(self):
        write(self.root, TODO, 'struct DriftProbe {}\nstruct DriftProbeTwin {}\n')
        result = self.run_check('3')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(TODO + ':DriftProbe:', result.stdout)
        self.assertIn(TODO + ':DriftProbeTwin:', result.stdout)
        print('RED gate 3: DriftProbe and DriftProbeTwin (2 dead declarations)')

    def test_test_only_probe(self):
        write(self.root, TODO, 'struct DriftTestOnly {}\n')
        write(self.root, 'Tests/drift-test.swift', 'let probe = DriftTestOnly()\n')
        self.red('3', 'test-only: ' + TODO + ':DriftTestOnly')

    def test_dead_func_static_and_global(self):
        write(self.root, TODO, 'func driftFunction() {}\nlet driftGlobal = 0\n'
              'struct Existing {\n    static let driftStatic = 1\n}\n')
        self.red('3', ':driftFunction:')
        result = self.run_check('3')
        self.assertIn(':driftGlobal:', result.stdout)
        self.assertIn(':driftStatic:', result.stdout)

    def test_dead_waiver(self):
        write(self.root, TODO, 'struct DriftProbe {} // drift: keep fixture API\n')
        self.assertEqual(self.run_check('3').returncode, 0)

    def test_callback_and_wrapper_exemptions(self):
        write(self.root, TODO, '@objc func fixtureCallback() {}\n@main struct FixtureMain {}\n'
              'override func fixtureOverride() {}\n@propertyWrapper struct FixtureWrapper {}\n')
        self.assertEqual(self.run_check('3').returncode, 0)

    def test_copied_key_literal(self):
        write(self.root, TODO, 'let firstKey = "todo-drift.probe"\n')
        write(self.root, 'Tinycast/Features/Treadmill/DriftProbe.swift', 'let secondKey = "todo-drift.probe"\n')
        self.red('4', 'constants: todo-drift.probe: 2 > 0')

    def test_sf_symbols_and_comments_excluded(self):
        for feature in ('Todo', 'Treadmill'):
            write(self.root, f'Tinycast/Features/{feature}/Symbols.swift',
                  'Image(systemName: "arrow.clockwise")\nLabel("Refresh", systemImage: "arrow.clockwise")\n'
                  '// let comment = "comment.not-key"\n/* let nested = "nested.not-key" */\n')
        result = self.run_check('4')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_constant_waiver(self):
        for feature in ('Todo', 'Treadmill'):
            write(self.root, f'Tinycast/Features/{feature}/Constants.swift',
                  'let key = "todo-drift.probe" // drift: keep fixture protocol\n')
        self.assertEqual(self.run_check('4').returncode, 0)

    def test_clean_15_line_clone(self):
        block = '\n'.join((ROOT / CLEAN).read_text().splitlines()[20:35]) + '\n'
        write(self.root, TODO, block)
        self.red('4', 'clones: ')

    def test_battery_clone(self):
        write(self.root, 'Tinycast/Features/Todo/DriftBig.swift', (ROOT / BATTERY).read_text())
        self.red('4', 'clones: ')

    def test_jscpd_failure_closes_gate(self):
        binary = Path(self.work.name) / 'bin'
        binary.mkdir()
        write(binary, 'npx', '#!/bin/sh\nprintf "offline fixture\\n" >&2\nexit 19\n')
        (binary / 'npx').chmod(0o755)
        env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'])
        result = self.run_check('4', env=env)
        self.assertEqual(result.returncode, 1)
        self.assertIn('jscpd failed (19)', result.stderr)
        print('RED gate 4: unavailable clone checker fails closed (exit 19)')

    def test_lower_budget_required(self):
        baseline = self.baseline()
        baseline['file-size'][BATTERY] += 1
        self.save_baseline(baseline)
        self.red('2', 'lower it in drift-baseline.json')

    def test_removed_budget_key_requires_tightening(self):
        baseline = self.baseline()
        baseline['file-size']['Tinycast/Features/Todo/Deleted.swift'] = 401
        self.save_baseline(baseline)
        self.red('2', '0 < 401; lower it')

    def test_baseline_raise_refused(self):
        baseline = self.baseline()
        baseline['file-size'][BATTERY] += 1
        self.save_baseline(baseline)
        result = self.run_check('2', '--compare-base', 'HEAD')
        self.assertEqual(result.returncode, 1)
        self.assertIn('455 > 454', result.stdout)

    def test_added_zero_budget_key_refused(self):
        baseline = self.baseline()
        baseline['dead']['new-key'] = 0
        self.save_baseline(baseline)
        result = self.run_check('3', '--compare-base', 'HEAD')
        self.assertEqual(result.returncode, 1)

    def test_report_stub_hook_one_crossing_and_zero_on_rerun(self):
        baseline = self.baseline()
        baseline['alerts'] = dict.fromkeys(baseline['alerts'], 999999)
        baseline['alerts']['try?'] = 0
        self.save_baseline(baseline)
        write(self.root, TODO, 'let result = try? fixtureOperation()\n')
        home = Path(self.work.name) / 'home'
        calls = home / 'calls'
        write(home, '.config/notchcast/private.env',
              'notchcast_task() { printf "%s\\n%s\\n" "$1" "$2" >> "$HOME/calls"; }\n')
        env = dict(os.environ, HOME=str(home))
        first = self.run_check('1,2,3', '--report', env=env)
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertEqual(len(calls.read_text().splitlines()), 2)
        second = self.run_check('1,2,3', '--report', env=env)
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(len(calls.read_text().splitlines()), 2)
        print('PASS gate 5: stub hook called 1 time on crossing, 0 times on rerun')

    def test_empty_waiver_reason_does_not_pass(self):
        write(self.root, TODO, 'struct DriftProbe {} // drift: keep \n')
        self.red('3', ':DriftProbe:')

    def test_report_counts_landed_fix_waivers(self):
        git(self.root, 'commit', '--allow-empty', '-qm', 'Notchcast: Fix fixture', '-m', 'No test: fixture proof')
        result = self.run_check('1,2,3', '--report', env=dict(os.environ, HOME=str(Path(self.work.name) / 'home')))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('fix-no-test | 1 | 0', result.stdout)

    def test_missing_alert_threshold_fails_closed(self):
        baseline = self.baseline()
        del baseline['alerts']['try?']
        self.save_baseline(baseline)
        result = self.run_check('1')
        self.assertEqual(result.returncode, 1)
        self.assertIn('baseline alerts must define every report counter', result.stderr)

    def test_report_without_hook(self):
        home = Path(self.work.name) / 'home'
        env = dict(os.environ, HOME=str(home))
        result = self.run_check('1,2,3', '--report', env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('no task hook', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
