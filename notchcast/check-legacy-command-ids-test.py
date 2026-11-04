#!/usr/bin/env python3
"""Exercise the legacy guard against the shipped command and identity regressions."""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location(
    "legacy_ids", Path(__file__).with_name("check-legacy-command-ids.py"))
GUARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUARD)


class LegacyCommandIDTests(unittest.TestCase):
    def test_shipped_command(self):
        self.assertEqual(GUARD.check(GUARD.ROOT), [])

    def test_identity_regressions(self):
        source = (GUARD.ROOT / GUARD.COMMAND).read_text()
        literal = 'legacyID: "command:toggle-island"'
        self.assertIn(literal, source)
        for replacement in ('legacyID: "command:nc-toggle-island"',
                            '/* ' + literal + ' */', '// ' + literal + '\n',
                            'legacyID: nil', ''):
            with self.subTest(replacement=replacement), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path = root / GUARD.COMMAND
                path.parent.mkdir(parents=True)
                path.write_text(source.replace(literal, replacement))
                self.assertTrue(GUARD.check(root))

    def test_missing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertTrue(GUARD.check(Path(directory)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
