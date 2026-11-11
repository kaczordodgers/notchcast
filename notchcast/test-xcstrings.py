#!/usr/bin/env python3
"""Standalone catalog merge and PR policy harness."""
import json
import itertools
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
tool = runpy.run_path(str(ROOT / "xcstrings-union.py"))
merge, dump = tool["merge"], tool["dump"]
check = runpy.run_path(str(ROOT / "check-xcstrings-order.py"))["check"]


def catalog(**strings):
    return dump({"sourceLanguage": "en", "strings": strings, "version": "1.0"}) + "\n"


class CatalogTests(unittest.TestCase):
    def test_migration_current_contexts(self):
        rewrite = runpy.run_path(str(ROOT / 'move-fork-strings.py'))['rewrite']
        source = ('SettingsFilterField(prompt: "Fork", query: $query)\n'
                  'Section("Fork") {}\n.help("Fork")\n')
        result, count = rewrite(source, {'Fork'})
        self.assertEqual(count, 3)
        self.assertEqual(rewrite(result, {'Fork'}), (result, 0))
        source = ('Logger(subsystem: "app", category: "Recording")\n'
                  'NSError(domain: "Distill")\nDownloadTool(name: "aria2c")\n'
                  'ExecutableLocator.find("aria2c")\n'
                  'url.appending(path: "Downloads")\n'
                  'url.appendingPathComponent("Downloads")\n'
                  '"com.apple.Battery-Settings.extension": "Battery"\n'
                  'entry(keywords: ["Remote Mac address"])\n'
                  'let script = """\n tell application "Finder"\n """')
        keys = {'Recording', 'Distill', 'aria2c', 'Downloads', 'Battery',
                'Remote Mac address', 'Finder'}
        self.assertEqual(rewrite(source, keys), (source, 0))
        self.assertEqual(rewrite('case "Finder": break', {'Finder'}),
                         ('case "Finder": break', 0))
        result, count = rewrite('String(\n localized: "Fork")', {'Fork'})
        self.assertEqual(count, 1)
        self.assertIn('table: "Notchcast"', result)

    def test_migration_rewrites_and_is_idempotent(self):
        rewrite = runpy.run_path(str(ROOT / 'move-fork-strings.py'))['rewrite']
        source = ('Text("Fork")\nString(localized: "Fork")\n'
                  'LocalizedStringResource("Fork")\nSettingsRowTitle(.group, "Fork")\n'
                  'TextField("Fork", text: $query)\nText("Shared")\n')
        result, count = rewrite(source, {'Fork'})
        self.assertEqual(count, 5)
        self.assertEqual(result.count('"Notchcast"'), 5)
        self.assertIn('Text("Shared")', result)
        self.assertEqual(rewrite(result, {'Fork'}), (result, 0))
        result, count = rewrite('var title: LocalizedStringResource { switch self {\n'
                                'case .day: "Day"\n} }', {'Day', 'Notchcast'})
        self.assertEqual(count, 1)
        self.assertEqual(rewrite(result, {'Day', 'Notchcast'}), (result, 0))

    def test_migration_interpolation_comments_and_unknown_context(self):
        rewrite = runpy.run_path(str(ROOT / 'move-fork-strings.py'))['rewrite']
        source = '// Text("Fork")\nString(localized: "Updated \\(format(value))")'
        result, count = rewrite(source, {'Fork', 'Updated %@'})
        self.assertEqual(count, 1)
        self.assertIn('format(value))", table: "Notchcast"', result)
        with self.assertRaisesRegex(ValueError, 'unrecognized'):
            rewrite('unknown("Fork")', {'Fork'})

    def test_interpolated_references(self):
        for spec in ('%@', '%lld', '%ld', '%d', '%f', '%.2f', '%1$@',
                     '%lf', '%llu', '%lu', '%u'):
            key = 'Updated ' + spec
            swift = r'Text("Updated \(format(value))")'
            self.assertFalse(check({}, {key: {}}, swift, ''))
            self.assertTrue(check({key: {}}, {}, '', swift))
        self.assertFalse(check({}, {'Transcribing %lld of %lld': {}},
                               r'Text("Transcribing \(count) of \(total)")', ''))

    def test_nested_interpolation(self):
        swift = r'String(localized: "About \(approximate.formatted(.byteCount(style: .file))) on disk")'
        key = 'About %@ on disk'
        self.assertFalse(check({}, {key: {}}, swift, ''))
        self.assertTrue(check({key: {}}, {}, '', swift))
        self.assertTrue(check({}, {'About %@ elsewhere': {}}, swift, ''))

    def test_allow_list_guidance(self):
        errors = check({}, {'Intentional': {}}, '', '')
        self.assertIn('notchcast/xcstrings-allowed-keys.json', errors[0])
        self.assertFalse(check({}, {'Intentional': {}}, '', '', ['Intentional']))

    def test_branch_edit(self):
        base = catalog(Key={'value': 'old'})
        branch = catalog(Key={'value': 'fixed'})
        self.assertEqual(merge(base, base, branch), branch)

    def test_multiline_and_percent(self):
        self.assertFalse(check({}, {'Warns below %lld%%.': {}},
                               r'Text("Warns below \(10)%.")', ''))
        self.assertFalse(check({}, {'Only these folders are indexed.': {}},
                               'Text("""\n    Only these folders are \\\n    indexed.\n    """)', ''))

    def test_delete_edit_conflict(self):
        base = catalog(Key={'value': 'old'})
        edited = catalog(Key={'value': 'fixed'})
        for main, branch in ((edited, catalog()), (catalog(), edited)):
            with self.assertRaisesRegex(ValueError, 'value conflicts'):
                merge(base, main, branch)

    def test_character_order(self):
        result = merge(catalog(), catalog(Alpha={}, zebra={}), catalog(Zebra={}, apple={}))
        self.assertEqual(list(json.loads(result)['strings']), ['Alpha', 'Zebra', 'apple', 'zebra'])

    def test_crlf_cli(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / name for name in ('base', 'main', 'branch', 'out')]
            for path, value in zip(paths, (catalog(A={}), catalog(A={}), catalog(A={}, B={}))):
                path.write_bytes(value.replace('\n', '\r\n').encode())
            result = subprocess.run(['python3', str(ROOT / 'xcstrings-union.py'),
                                     *map(str, paths)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            raw = paths[-1].read_bytes()
            self.assertIn(b'\r\n', raw)
            self.assertNotIn(b'\n', raw.replace(b'\r\n', b''))

    def test_identity(self):
        text = (ROOT.parent / tool["CATALOG"]).read_text()
        self.assertEqual(merge(text, text, text), text)

    def test_deletions_additions_and_order(self):
        base = catalog(Alpha={}, Deleted={}, Omega={})
        main = catalog(Alpha={}, Omega={})
        branch = catalog(Alpha={}, Beta={}, Deleted={}, Omega={})
        result = merge(base, main, branch)
        self.assertEqual(list(json.loads(result)["strings"]), ["Alpha", "Beta", "Omega"])
        self.assertEqual(merge(base, branch, main), result)
        self.assertEqual(merge(base, main, catalog(Omega={})), catalog(Omega={}))

    def test_conflicts(self):
        with self.assertRaisesRegex(ValueError, "value conflicts"):
            merge(catalog(Key={"value": "old"}), catalog(Key={"value": "main"}),
                  catalog(Key={"value": "branch"}))

    def test_conflict_cli_keeps_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / name for name in ('base', 'main', 'branch', 'out')]
            for path, value in zip(paths, ('old', 'main', 'branch')):
                path.write_text(catalog(Key={'value': value}))
            paths[-1].write_text('untouched')
            result = subprocess.run(['python3', str(ROOT / 'xcstrings-union.py'),
                                     *map(str, paths)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('value conflicts', result.stderr)
            self.assertEqual(paths[-1].read_text(), 'untouched')

    def test_preserves_upstream_text(self):
        main = catalog(Zebra={'value': 'main'}, Alpha={}).replace('"value" :', '"value":')
        result = merge(catalog(), main, catalog(Beta={}))
        self.assertIn('"value": "main"', result)
        self.assertEqual(list(json.loads(result)['strings']), ['Beta', 'Zebra', 'Alpha'])

    def test_empty_and_last(self):
        self.assertEqual(json.loads(merge(catalog(A={}), catalog(A={}), catalog()))["strings"], {})
        self.assertEqual(list(json.loads(merge(catalog(), catalog(), catalog(Z={})))['strings']), ['Z'])

    def test_check(self):
        self.assertTrue(check(dict(A={}, B={}), dict(B={}, A={}), '', ''))
        self.assertTrue(check({}, dict(Restored={}), '', ''))
        self.assertFalse(check({}, dict(New={}), 'Text("New")', ''))
        self.assertTrue(check(dict(A={}), {}, '', 'Text("A")'))
        self.assertFalse(check(dict(A={}), {}, '', ''))
        self.assertFalse(check({}, dict(Listed={}), '', '', ['Listed']))

    def test_git_operations(self):
        for operation, catalog_path in itertools.product(
                ('branch-first', 'main-first', 'rebase', 'cherry-pick'),
                (tool['CATALOG'], 'Tinycast/Resources/Notchcast.xcstrings')):
            with self.subTest(operation=operation), tempfile.TemporaryDirectory() as directory:
                def git(*args, check=True):
                    return subprocess.run(['git', '-C', directory, *args], cwd=directory, check=check,
                                          capture_output=True, text=True)
                git('init', '-b', 'main')
                git('config', 'user.name', 'Catalog Test')
                git('config', 'user.email', 'test@example.com')
                path = Path(directory) / catalog_path
                path.parent.mkdir(parents=True)
                base = catalog(Alpha={}, Deleted={}, Key={'value': 'old'}, Omega={})
                path.write_text(base)
                git('add', '.')
                git('commit', '-m', 'base')
                git('checkout', '-b', 'branch')
                branch = catalog(Alpha={}, Beta={}, Deleted={}, Key={'value': 'old'}, Omega={})
                path.write_text(branch.replace('"value" : "old"', '"value": "old"'))
                git('commit', '-am', 'branch')
                git('checkout', 'main')
                main = catalog(Alpha={}, Key={'value': 'main'}, Omega={})
                path.write_text(main)
                git('commit', '-am', 'main')
                if operation in ('branch-first', 'rebase'):
                    git('checkout', 'branch')
                if operation == 'branch-first':
                    git('merge', '--no-commit', 'main', check=False)
                elif operation == 'main-first':
                    git('merge', '--no-commit', 'branch', check=False)
                elif operation == 'rebase':
                    git('rebase', 'main', check=False)
                else:
                    git('cherry-pick', 'branch', check=False)
                result = subprocess.run(['python3', str(ROOT / 'xcstrings-union.py'),
                                         '--git', '--main-ref', 'main', '--catalog', catalog_path], cwd=directory,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(path.read_text(), merge(base, main, branch))


if __name__ == "__main__":
    unittest.main()
