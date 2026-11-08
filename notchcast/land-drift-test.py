#!/usr/bin/env python3
"""Exercise land.sh's actual baseline gate and defect-test rule in isolated repositories."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('fixtures', ROOT / 'notchcast/check-drift-test.py')
fixtures = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixtures)
LAND = (ROOT / 'notchcast/land.sh').read_text()
DEFECT = re.search(r'^check_defect_tests\(\) \{\n.*?^\}', LAND, re.M | re.S)[0]
BASELINE = next(line.strip() for line in LAND.splitlines() if '--compare-base "$onto"' in line)


class Landing(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixtures.Gates.setUpClass()

    @classmethod
    def tearDownClass(cls):
        fixtures.Gates.tearDownClass()

    def setUp(self):
        self.fixture = fixtures.Gates(methodName='test_clean_fixture')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        fixtures.write(self.root, 'notchcast/check-drift.py', (ROOT / 'notchcast/check-drift.py').read_text())
        fixtures.write(self.root, 'notchcast/bin/swiftgraph.py', (ROOT / 'notchcast/bin/swiftgraph.py').read_text())

    def shell(self, script, *args):
        return subprocess.run(['bash', '-c', 'set -euo pipefail\n'
                               'refuse() { printf "REFUSED: %s\\n" "$*"; exit 1; }\n' + script,
                               'landing-fixture', *args], cwd=self.root, capture_output=True, text=True)

    def test_manually_raised_entry_refuses_in_land(self):
        baseline = self.fixture.baseline()
        baseline['file-size'][fixtures.BATTERY] += 1
        self.fixture.save_baseline(baseline)
        result = self.shell('onto=HEAD\n' + BASELINE)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('REFUSED: drift baseline grew', result.stdout)
        self.assertIn('455 > 454', result.stdout)
        print(result.stdout.strip())

    def test_added_entry_refuses_in_land(self):
        baseline = self.fixture.baseline()
        baseline['dead']['new-entry'] = 1
        self.fixture.save_baseline(baseline)
        result = self.shell('onto=HEAD\n' + BASELINE)
        self.assertEqual(result.returncode, 1)
        self.assertIn('REFUSED: drift baseline grew', result.stdout)

    def test_lowered_entry_is_allowed(self):
        baseline = self.fixture.baseline()
        baseline['file-size'][fixtures.BATTERY] -= 1
        self.fixture.save_baseline(baseline)
        result = self.shell('onto=HEAD\n' + BASELINE)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_defect_test_rule(self):
        base = fixtures.git(self.root, 'rev-parse', 'HEAD')
        paths = ('notes.txt', 'Tests/probe-test.swift', 'notchcast/probe-test.py',
                 'notchcast/nested/probe-test.sh', 'Tests/not-a-harness.swift')
        for path in paths:
            with self.subTest(path=path):
                fixtures.write(self.root, path, 'fixture\n')
                fixtures.git(self.root, 'add', path)
                fixtures.git(self.root, 'commit', '-qm', 'Fixture change')
                head = fixtures.git(self.root, 'rev-parse', 'HEAD')
                is_test = '-test.' in path
                result = self.shell(DEFECT + '\ncheck_defect_tests "$1" "$2" "$3" "$4"',
                                    base, head, 'Notchcast: Fix probe', '')
                self.assertEqual(result.returncode, 0 if is_test else 1, result.stdout + result.stderr)
                if not is_test:
                    self.assertIn('REFUSED: defect fix needs a changed test', result.stdout)
                base = head
        for title, body, code in [('Notchcast: Fix probe', 'No test: documentation only', 0),
                                  ('Notchcast: Fix probe', 'No test: ', 1),
                                  ('Notchcast: Fix probe', 'No test:', 1),
                                  ('Notchcast: Add probe', '', 0)]:
            result = self.shell(DEFECT + '\ncheck_defect_tests "$1" "$2" "$3" "$4"',
                                base, base, title, body)
            self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        print('PASS: defect fixes require a changed harness or a nonempty No test reason')

    def test_wiring_order_and_nonblocking_report(self):
        shape = LAND.index("python3 notchcast/check-feature-shape.py || refuse 'feature shape'")
        budget = LAND.index(BASELINE)
        drift = LAND.index("python3 notchcast/check-drift.py || refuse 'drift'")
        fixtures_gate = LAND.index("python3 notchcast/check-drift-test.py || refuse 'drift fixtures'")
        self.assertLess(shape, budget)
        self.assertLess(budget, drift)
        self.assertLess(drift, fixtures_gate)
        self.assertLess(fixtures_gate, LAND.index('typecheck=$(swiftc'))
        self.assertLess(LAND.index('git push origin "$commit:refs/heads/main"'),
                        LAND.index('python3 notchcast/check-drift.py --report'))
        report = next(line.strip() for line in LAND.splitlines() if 'check-drift.py --report' in line)
        fixtures.write(self.root, 'notchcast/check-drift.py', 'raise SystemExit(19)\n')
        result = self.shell(report + '\nprintf "landing survived report failure\\n"')
        self.assertEqual(result.returncode, 0)
        self.assertIn('landing survived report failure', result.stdout)
        self.assertIn('WARN: drift report failed after landing', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
