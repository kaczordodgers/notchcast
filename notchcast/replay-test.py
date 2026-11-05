#!/usr/bin/env python3
"""Exercise replay's catalog resolution and conflict boundaries in isolated repositories."""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("ci", Path(__file__).with_name("ci.py"))
CI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI)
CATALOG = "Tinycast/Resources/Localizable.xcstrings"


class ReplayTests(unittest.TestCase):
    def scenario(self, column_zero=False, conflict=None, later_conflict=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            def catalog(entries):
                text = json.dumps({"sourceLanguage": "en", "strings": entries, "version": "1.0"}, indent=2) + "\n"
                if column_zero:
                    text = text.replace('    "', '"')
                path = root / CATALOG
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            def commit(message):
                git("add", ".")
                git("commit", "-qm", message)
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("config", "core.hooksPath", "/dev/null")
            catalog({"a": {}, "z": {}})
            (root / "other").write_text("base\n")
            commit("base")
            base = git("rev-parse", "HEAD")
            catalog({"a": {}, "ours": {}, "z": {}})
            if conflict == "other":
                (root / "other").write_text("ours\n")
            commit("ours")
            if later_conflict:
                (root / "other").write_text("ours\n")
                commit("later conflict")
            ours = git("rev-parse", "HEAD")
            git("checkout", "-q", "--detach", base)
            entries = {"a": {}, "upstream": {}, "z": {}}
            if conflict == "catalog":
                entries["ours"] = {"comment": "different"}
            if conflict == "deleted catalog":
                git("rm", CATALOG)
            else:
                catalog(entries)
            (root / "other").write_text("upstream\n")
            commit("upstream")
            upstream = git("rev-parse", "HEAD")
            git("update-ref", "refs/remotes/upstream/main", upstream)
            git("checkout", "-q", "--detach", ours)
            if conflict or later_conflict:
                with self.assertRaises(CI.Conflict) as caught:
                    CI.replay(root, upstream, check=True)
                self.assertEqual(caught.exception.subject, "later conflict" if later_conflict else "ours")
                self.assertEqual(caught.exception.files,
                                 ["other"] if later_conflict or conflict == "other" else [CATALOG])
            else:
                CI.replay(root, upstream, check=True)
                self.assertEqual(set(json.loads((root / CATALOG).read_text())["strings"]),
                                 {"a", "ours", "upstream", "z"})
                self.assertEqual(git("diff", "--name-only", "--diff-filter=U"), "")

    def test_adjacent_additions(self):
        self.scenario()

    def test_column_zero(self):
        self.scenario(column_zero=True)

    def test_value_conflict(self):
        self.scenario(conflict="catalog")

    def test_upstream_deletes_catalog(self):
        self.scenario(conflict="deleted catalog")

    def test_other_conflict(self):
        self.scenario(conflict="other")

    def test_resolution_does_not_mask_later_failure(self):
        self.scenario(later_conflict=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
