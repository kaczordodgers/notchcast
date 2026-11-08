#!/usr/bin/env python3
"""Prove the literal guard rejects drift and unlisted copies."""
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
CONFIG = runpy.run_path(str(ROOT / 'notchcast/ci.py'))['config']()


class ConfigTests(unittest.TestCase):
    def test_literal_mutation(self):
        manifest = json.loads((ROOT / 'notchcast/config-literals.json').read_text())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            for path in [*manifest, 'notchcast/config-literals.json', 'notchcast/config.env',
                         'notchcast/check-config.py', 'notchcast/ci.py']:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / path, target)

            def check():
                return subprocess.run(['python3', str(root / 'notchcast/check-config.py')],
                                      cwd=root, capture_output=True, text=True)

            for path in ('Scripts/release-notes.sh', '.github/workflows/upstream-release.yml'):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(CONFIG['UPSTREAM_REPO'] + '\n')
            self.assertEqual(check().returncode, 0)
            print('PASS upstream-owned files do not affect the literal guard')
            for path in ('notchcast/README.public.md', '.github/CONTRIBUTING.md',
                         '.github/SECURITY.md', '.github/ISSUE_TEMPLATE/notchcast-bug.yml'):
                target = root / path
                original = target.read_text()
                target.write_text(original.replace(CONFIG['FORK_REPO'], 'different/repository'))
                red = check()
                self.assertEqual(red.returncode, 1, red.stdout + red.stderr)
                self.assertIn(path, red.stdout)
                print('RED deliberate literal edit: ' + red.stdout.strip())
                target.write_text(original)
                green = check()
                self.assertEqual(green.returncode, 0, green.stdout + green.stderr)
                print('GREEN restored literal: ' + green.stdout.strip())
            (root / 'notchcast/duplicate.sh').write_text(CONFIG['FORK_REPO'])
            duplicate = check()
            self.assertEqual(duplicate.returncode, 1, duplicate.stdout + duplicate.stderr)
            self.assertIn('notchcast/duplicate.sh', duplicate.stdout)

    def test_live_inventory(self):
        result = subprocess.run(['python3', str(ROOT / 'notchcast/check-config.py')],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
