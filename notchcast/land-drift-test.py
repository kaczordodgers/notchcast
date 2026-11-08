#!/usr/bin/env python3
"""Exercise landing drift behavior in isolated repositories with generated sources."""
import importlib.util
import os
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
BASELINE = next(line.strip() for line in LAND.splitlines() if '--compare-base "$onto"' in line)


def function(name):
    return re.search(r'^' + name + r'\(\) \{\n.*?^\}', LAND, re.M | re.S)[0]


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

    def shell(self, script, *args, env=None):
        return subprocess.run(['bash', '-c', 'set -euo pipefail\n'
                               'refuse() { printf "REFUSED: %s\\n" "$*"; exit 1; }\n'
                               'drift_tools="$PWD/notchcast"\n' + script,
                               'landing-fixture', *args], cwd=self.root, capture_output=True, text=True, env=env)

    def commit(self, message):
        fixtures.git(self.root, 'add', '-A')
        fixtures.git(self.root, 'commit', '-qm', message)
        return fixtures.git(self.root, 'rev-parse', 'HEAD')

    def tooling(self, base, body, base_fixtures='raise SystemExit(0)\n'):
        tools = Path(self.fixture.work.name) / 'base-tools'
        fixtures.write(tools, 'check-drift-test.py', base_fixtures)
        script = (function('drift_fixtures_changed') + '\n' + function('check_drift_tooling') + '\n'
                  + function('squash_message') + '\n'
                  + 'check_drift_tooling "$1" "$2" "$3"\npr=7\npr_title="Notchcast: Tune drift"\npr_body="$2"\nsquash_message')
        return self.shell(script, base, body, str(tools))

    def test_manually_raised_entry_refuses_in_land(self):
        baseline = self.fixture.baseline()
        baseline['file-size'][fixtures.LARGE] += 1
        self.fixture.save_baseline(baseline)
        result = self.shell('onto=HEAD\n' + BASELINE)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('REFUSED: drift baseline grew', result.stdout)
        self.assertIn(f'{fixtures.LARGE_LINES + 1} > {fixtures.LARGE_LINES}', result.stdout)
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
        baseline['file-size'][fixtures.LARGE] -= 1
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
                result = self.shell(function('check_defect_tests') + '\ncheck_defect_tests "$1" "$2" "$3" "$4"',
                                    base, head, 'Notchcast: Fix probe', '')
                self.assertEqual(result.returncode, 0 if '-test.' in path else 1, result.stdout + result.stderr)
                base = head
        for title in ('Notchcast: Fix probe', 'Notchcast: fix probe', 'Notchcast: FIX probe', 'Fix probe', 'fix probe'):
            for body, code in [('No test: documentation only', 0), ('No test: ', 1), ('No test:', 1), ('', 1)]:
                with self.subTest(title=title, body=body):
                    result = self.shell(function('check_defect_tests') + '\ncheck_defect_tests "$1" "$2" "$3" "$4"',
                                        base, base, title, body)
                    self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        result = self.shell(function('check_defect_tests') + '\ncheck_defect_tests HEAD HEAD "Notchcast: Add probe" ""')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_refresh_removes_upstream_additions_from_fork_scope(self):
        remote = Path(self.fixture.work.name) / 'upstream'
        fixtures.git(self.root, 'clone', '-q', str(self.fixture.seed), str(remote))
        fixtures.git(remote, 'config', 'user.name', 'Fixture')
        fixtures.git(remote, 'config', 'user.email', 'fixture@example.com')
        fixtures.git(remote, 'checkout', '-qb', 'main', self.fixture.upstream)
        fixtures.write(remote, 'Tinycast/Features/Launcher/NewUpstream.swift', 'struct NewUpstream {}\n')
        fixtures.git(remote, 'add', '.')
        fixtures.git(remote, 'commit', '-qm', 'New upstream source')
        fixtures.git(self.root, 'remote', 'add', 'upstream', str(remote))
        fixtures.git(self.root, 'fetch', '-q', 'upstream', 'main')
        fixtures.git(self.root, 'merge', '--no-edit', 'upstream/main')
        fixtures.git(self.root, 'update-ref', 'refs/remotes/upstream/main', self.fixture.upstream)
        command = [sys.executable, str(fixtures.CHECK), '--root', str(self.root), '--gates', '1']
        before = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(before.returncode, 1, before.stdout + before.stderr)
        self.assertIn('upstream-folders:', before.stdout)
        result = self.shell(function('refresh_upstream') + '\nrefresh_upstream')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        after = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(after.returncode, 0, after.stdout + after.stderr)
        print('PASS: refreshing stale upstream stops charging its new file to the fork')

    def test_main_tooling_cannot_be_replaced_by_candidate(self):
        fixtures.write(self.root, 'notchcast/check-drift.py', 'print("base checker")\nraise SystemExit(7)\n')
        fixtures.git(self.root, 'add', 'notchcast')
        fixtures.git(self.root, 'commit', '-qm', 'Base checker')
        base = fixtures.git(self.root, 'rev-parse', 'HEAD')
        fixtures.write(self.root, 'notchcast/check-drift.py', 'print("candidate bypass")\n')
        result = self.shell(function('prepare_drift_tools') + '\n'
                            'scratch="$1"\ntop="$PWD"\nprepare_drift_tools "$2"\n'
                            'python3 "$drift_tools/check-drift.py"', self.fixture.work.name, base)
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertIn('base checker', result.stdout)
        self.assertNotIn('candidate bypass', result.stdout)

    def test_tooling_change_needs_signoff_kept_in_message(self):
        fixtures.write(self.root, 'notchcast/check-drift-test.py', 'print("base copy")\n')
        base = self.commit('Base tooling')
        fixtures.write(self.root, 'notchcast/check-drift-test.py', 'print("candidate fixtures")\n')
        self.commit('Candidate tooling')
        refused = self.tooling(base, 'Summary only')
        self.assertEqual(refused.returncode, 1, refused.stdout + refused.stderr)
        self.assertIn('REFUSED: drift tooling or land.sh changed', refused.stdout)
        passed = self.tooling(base, 'Summary\nDrift tooling: tighten the clone fixture')
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)
        self.assertIn('\n\nDrift tooling: tighten the clone fixture\n', passed.stdout)
        self.assertEqual((self.root / 'notchcast/check-drift-test.py').read_text(), 'print("candidate fixtures")\n')
        print('PASS: tooling change refused without Drift tooling:, and the line reaches the squash message')

    def test_land_change_needs_signoff(self):
        base = self.commit('Base')
        fixtures.write(self.root, 'notchcast/land.sh', 'echo changed\n')
        self.commit('Candidate land.sh')
        refused = self.tooling(base, '')
        self.assertEqual(refused.returncode, 1, refused.stdout + refused.stderr)
        self.assertIn('REFUSED: drift tooling or land.sh changed', refused.stdout)
        passed = self.tooling(base, 'Drift tooling: land.sh retry wording')
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)
        self.assertIn('Drift tooling: land.sh retry wording', passed.stdout)

    def test_sourced_helper_change_needs_signoff(self):
        base = self.commit('Base')
        fixtures.write(self.root, 'notchcast/hold.sh', 'refuse() { echo "WARN: $*"; }\n')
        self.commit('Candidate hold.sh')
        refused = self.tooling(base, 'Summary only')
        self.assertEqual(refused.returncode, 1, refused.stdout + refused.stderr)
        self.assertIn('REFUSED: drift tooling or land.sh changed', refused.stdout)

    def test_unrelated_change_needs_no_signoff(self):
        base = self.commit('Base')
        fixtures.write(self.root, 'notes.txt', 'unrelated\n')
        self.commit('Unrelated')
        result = self.tooling(base, '')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, 'Notchcast: Tune drift (#7)\n')

    def test_deleted_fixtures_refused_cleanly(self):
        fixtures.write(self.root, 'notchcast/check-drift-test.py', 'print("base copy")\n')
        base = self.commit('Base tooling')
        (self.root / 'notchcast/check-drift-test.py').unlink()
        self.commit('Delete fixtures')
        result = self.tooling(base, 'Drift tooling: drop fixtures')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('REFUSED: the PR deletes notchcast/check-drift-test.py', result.stdout)
        self.assertNotIn('error:', result.stdout + result.stderr)

    def test_planted_module_cannot_shadow_base_fixtures(self):
        fixtures.write(self.root, 'notchcast/check-drift-test.py', 'print("base copy")\n')
        base = self.commit('Base tooling')
        fixtures.write(self.root, 'notchcast/check-drift-test.py', 'print("candidate fixtures")\n')
        fixtures.write(self.root, 'notchcast/unittest.py', 'print("planted unittest")\nraise SystemExit(0)\n')
        self.commit('Candidate plants unittest')
        result = self.tooling(base, 'Drift tooling: probe', 'import unittest\nprint("base fixtures")\nraise SystemExit(7)\n')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('base fixtures', result.stdout)
        self.assertNotIn('planted unittest', result.stdout)
        self.assertIn('REFUSED: drift fixtures', result.stdout)

    def test_first_report_files_crossing_added_by_landing(self):
        baseline = self.fixture.baseline()
        baseline['alerts'] = dict.fromkeys(baseline['alerts'], 999999)
        baseline['alerts']['file-lines'] = 20
        self.fixture.save_baseline(baseline)
        for index in range(10):
            fixtures.write(self.root, f'Tinycast/Features/Todo/Over{index}.swift', '\n' * 21)
        base = self.commit('Base with 10 over-limit files')
        fixtures.write(self.root, 'Tinycast/Features/Todo/Over10.swift', '\n' * 21)
        landed = self.commit('Landing adds one over-limit file')
        fixtures.git(self.root, 'update-ref', 'refs/remotes/upstream/main', self.fixture.upstream)
        home = Path(self.fixture.work.name) / 'home'
        calls = home / 'calls'
        fixtures.write(home, '.config/notchcast/private.env', 'notchcast_task() { printf "%s\\n" "$2" >> "$HOME/calls"; }\n')
        env = dict(os.environ, HOME=str(home))
        counts = []
        for _ in range(2):
            result = self.shell(function('drift_report') + '\ndrift_tools="$1"\ndrift_report "$2" "$3"',
                                str(ROOT / 'notchcast'), base, landed, env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('WARN', result.stderr)
            counts.append(len(calls.read_text().splitlines()) if calls.exists() else 0)
        self.assertEqual(counts, [1, 1])
        self.assertIn('Tinycast/Features/Todo/Over10.swift', calls.read_text())
        print('PASS: no cache, base with 10 over-limit files: 1 hook call for the landed crossing, 0 on rerun')

    def test_red_base_is_reported_without_allowing_candidate(self):
        fixtures.write(self.root, 'notchcast/check-drift.py', 'raise SystemExit(9)\n')
        result = self.shell(function('check_drift') + '\nscratch="$1"\ncheck_drift HEAD "$drift_tools"',
                            self.fixture.work.name)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('main is already red', result.stderr)
        self.assertIn('REFUSED: drift', result.stdout)

    def test_drift_fixtures_only_for_tooling_changes(self):
        fixtures.git(self.root, 'add', 'notchcast')
        fixtures.git(self.root, 'commit', '-qm', 'Fixture tooling')
        base = fixtures.git(self.root, 'rev-parse', 'HEAD')
        fixtures.write(self.root, 'notes.txt', 'unrelated\n')
        fixtures.git(self.root, 'add', '.')
        fixtures.git(self.root, 'commit', '-qm', 'Unrelated')
        result = self.shell(function('drift_fixtures_changed') + '\ndrift_fixtures_changed "$1"', base)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for path in ('notchcast/check-drift.py', 'notchcast/check-drift-test.py',
                     'notchcast/bin/swiftgraph.py', 'notchcast/config.env'):
            fixtures.write(self.root, path, 'fixture tooling change\n')
            fixtures.git(self.root, 'add', path)
            fixtures.git(self.root, 'commit', '-qm', 'Tooling change')
            result = self.shell(function('drift_fixtures_changed') + '\ndrift_fixtures_changed "$1"', base)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            base = fixtures.git(self.root, 'rev-parse', 'HEAD')

    def test_nonblocking_report(self):
        report = next(line.strip() for line in LAND.splitlines() if '--report ||' in line)
        fixtures.write(self.root, 'notchcast/check-drift.py', 'raise SystemExit(19)\n')
        result = self.shell(report + '\nprintf "landing survived report failure\\n"')
        self.assertEqual(result.returncode, 0)
        self.assertIn('landing survived report failure', result.stdout)
        self.assertIn('WARN: drift report failed after landing', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
