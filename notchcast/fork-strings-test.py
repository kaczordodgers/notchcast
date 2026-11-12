#!/usr/bin/env python3
import json
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
TOOLS = runpy.run_path(str(ROOT / 'notchcast/move-fork-strings.py'))
CHECK = runpy.run_path(str(ROOT / 'notchcast/check-fork-strings.py'))['check']


def translated():
    return {'localizations': {locale: {'stringUnit': {'state': 'translated', 'value': 'Example'}}
                              for locale in TOOLS['LOCALES']}}


class ForkStringsTest(unittest.TestCase):
    def check(self, local, fork, source):
        upstream = {'Retry': translated()}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, strings in [(TOOLS['LOCAL'], local), (TOOLS['FORK'], fork)]:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps({'strings': strings}))
            (root / 'Tinycast/Example.swift').write_text(source)
            with patch.dict(CHECK.__globals__, ROOT=root), \
                    patch('runpy.run_path', return_value=TOOLS), \
                    patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, 'base\n')), \
                    patch('subprocess.check_output', return_value=json.dumps({'strings': upstream}).encode()):
                return CHECK()

    def test_upstream_owned_key_can_be_localized_in_both_tables(self):
        problems = self.check({'Retry': translated()}, {'Retry': translated()},
                              'Text("Retry")\nText("Retry", tableName: "Notchcast")')
        self.assertEqual(problems, [])

    def test_fork_only_key_cannot_enter_upstream_table(self):
        problems = self.check({'Retry': translated(), 'Fork action': translated()},
                              {'Fork action': translated()}, 'Text("Fork action", tableName: "Notchcast")')
        self.assertIn('fork key in Localizable: Fork action', problems)
        self.assertIn('key in both catalogs: Fork action', problems)

    def test_fork_only_reference_still_requires_explicit_table(self):
        problems = self.check({'Retry': translated()}, {'Fork action': translated()}, 'Text("Fork action")')
        self.assertTrue(any('fork literals use the default table' in problem for problem in problems))

    def test_shared_key_still_requires_every_translation(self):
        problems = self.check({'Retry': translated()}, {'Retry': {}}, 'Text("Retry", tableName: "Notchcast")')
        self.assertTrue(any('missing locales' in problem for problem in problems))

    def test_migration_preserves_upstream_calls_and_routes_fork_only_calls(self):
        upstream = json.dumps({'strings': {'Retry': translated()}}).encode()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            local = root / TOOLS['LOCAL']
            local.parent.mkdir(parents=True)
            local.write_bytes(upstream)
            (root / TOOLS['FORK']).write_text(json.dumps({
                'strings': {'Retry': translated(), 'Fork action': translated()}}))
            source = root / 'Tinycast/Example.swift'
            source.write_text('Text("Retry")\nText("Fork action")\n')
            plan = TOOLS['plan']
            with patch.dict(plan.__globals__, ROOT=root):
                changes, _, _ = plan(upstream)
            self.assertEqual(changes[source].decode(),
                             'Text("Retry")\nText("Fork action", tableName: "Notchcast")\n')
            self.assertNotIn(local, changes)

    def test_explicit_reference_still_requires_existing_key(self):
        problems = self.check({'Retry': translated()}, {}, 'Text("Missing", tableName: "Notchcast")')
        self.assertTrue(any('missing key' in problem for problem in problems))


if __name__ == '__main__':
    unittest.main()
