#!/usr/bin/env python3
"""Exercise replay's catalog resolution and conflict boundaries in isolated repositories."""
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("ci", Path(__file__).with_name("ci.py"))
CI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI)
CATALOG = "Tinycast/Resources/Localizable.xcstrings"


class RebaseHoldTests(unittest.TestCase):
    PR = {"number": 411, "isDraft": False, "isCrossRepository": False}

    def test_open_pr_holds_rebase(self):
        self.assertEqual(CI.rebase_hold([self.PR], 0, 8.8 * 3600),
                         (True, "open PRs #411; 3.2 h of 12 left"))

    def test_expired_hold_allows_rebase_with_warning(self):
        for hours in (12, 13):
            with self.subTest(hours=hours):
                self.assertEqual(CI.rebase_hold([self.PR], 0, hours * 3600),
                                 (False, "::warning::main: 12-hour hold expired with PRs #411 still open"))

    def test_no_open_pr_allows_rebase(self):
        self.assertEqual(CI.rebase_hold([], 0, 3600), (False, ""))

    def test_drafts_and_cross_repository_prs_do_not_hold(self):
        self.assertEqual(CI.rebase_hold([dict(self.PR, isDraft=True),
                                        dict(self.PR, isCrossRepository=True)], 0, 3600), (False, ""))

    def test_message_names_all_eligible_prs(self):
        self.assertEqual(CI.rebase_hold([dict(self.PR, number=412), self.PR], 0, 0),
                         (True, "open PRs #411, #412; 12.0 h of 12 left"))


class SyncWorkflowTests(unittest.TestCase):
    def job(self, name):
        text = (Path(__file__).resolve().parent.parent / ".github/workflows/sync.yml").read_text()
        match = re.search(rf"^  {name}:\n(.*?)(?=^  \S|\Z)", text, re.M | re.S)
        self.assertIsNotNone(match, name)
        return match[1]

    def test_release_failure_never_skips_main(self):
        """Releases run after main and from plan's main; main depends on plan alone, never on a release."""
        self.assertRegex(self.job("main"), r"(?m)^    needs: plan$")
        self.assertNotIn("release", re.search(r"(?m)^    if: (.*)$", self.job("main"))[1])
        self.assertRegex(self.job("release"), r"(?m)^    needs: \[plan, main\]$")


class TestedKeyTests(unittest.TestCase):
    def test_key_ignores_regenerated_files_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            def commit(files):
                for name, text in files.items():
                    (root / name).parent.mkdir(parents=True, exist_ok=True)
                    (root / name).write_text(text)
                git("add", ".")
                git("commit", "-qm", "c")
                return git("rev-parse", "HEAD")
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("config", "core.hooksPath", "/dev/null")
            plain = commit({"code": "one\n"})
            regenerated = [CI.PBXPROJ, CI.SCHEME, "README.md"]
            generated = commit({name: "regenerated\n" for name in regenerated})
            again = commit({name: "regenerated again\n" for name in regenerated})
            runtime = commit({CI.RUNTIME_JS: "rebuilt\n"})
            changed = commit({"code": "two\n"})
            self.assertEqual(CI.tested_key(plain, root), CI.tested_key(generated, root))
            self.assertEqual(CI.tested_key(generated, root), CI.tested_key(again, root))
            self.assertEqual(CI.tested_key(plain, root), git("rev-parse", f"{plain}^{{tree}}"))
            self.assertNotEqual(CI.tested_key(again, root), CI.tested_key(runtime, root))
            self.assertNotEqual(CI.tested_key(runtime, root), CI.tested_key(changed, root))
            self.assertEqual(git("diff", "--cached", "--name-only"), "")

    RUNS = {1: {"name": "PR", "path": ".github/workflows/pr.yml", "conclusion": "success", "head_repository": {"full_name": "Fork/Repo"}, "html_url": "run-1"}}

    def match(self, artifact, run=None):
        runs = {7: dict(self.RUNS[1], **(run or {}))}
        return CI.tested_run([dict({"workflow_run": {"id": 7}}, **artifact)], runs.__getitem__, "fork/repo")

    def test_green_pr_run_of_our_repo_matches(self):
        self.assertEqual(self.match({})["html_url"], "run-1")

    def test_every_other_run_is_rejected(self):
        for artifact, run in [({"expired": True}, None), ({}, {"conclusion": "failure"}), ({}, {"conclusion": None}),
                              ({}, {"name": "Sync"}), ({}, {"path": ".github/workflows/other.yml"}),
                              ({}, {"head_repository": {"full_name": "someone/repo"}}),
                              ({}, {"head_repository": None})]:
            with self.subTest(artifact=artifact, run=run):
                self.assertIsNone(self.match(artifact, run))

    def test_first_acceptable_artifact_wins_and_none_matches_nothing(self):
        artifacts = [{"expired": True, "workflow_run": {"id": 1}}, {"workflow_run": {"id": 1}}]
        self.assertEqual(CI.tested_run(artifacts, self.RUNS.__getitem__, "fork/repo")["html_url"], "run-1")
        self.assertIsNone(CI.tested_run([], self.RUNS.__getitem__, "fork/repo"))

    CFG = {"FORK_REPO": "fork/repo", "TESTED_CONTEXT": "ctx"}

    def reuse(self, responses, close_error=None):
        calls = []
        def fake(*cmd, **kwargs):
            calls.append(cmd)
            response = responses(cmd)
            if isinstance(response, Exception):
                raise response
            return response
        closer = mock.Mock(side_effect=close_error)
        with (mock.patch.object(CI, "tested_key", return_value="k" * 40), mock.patch.object(CI, "run", fake),
              mock.patch.object(CI, "issue_close", closer)):
            return CI.reuse_pr_build("main-sha", self.CFG), calls, closer

    @staticmethod
    def api(artifacts, run):
        def respond(cmd):
            path = cmd[-1] if cmd[2] != "-X" else None
            if path and "/artifacts?" in path:
                assert f"name=tested-tree-{'k' * 40}" in path
                return json.dumps({"artifacts": artifacts})
            return json.dumps(run) if path else ""
        return respond

    def test_match_posts_the_tested_status_with_the_run_url_and_closes_the_main_issue(self):
        found, calls, closer = self.reuse(self.api([{"workflow_run": {"id": 1}}], self.RUNS[1]))
        self.assertEqual(found["html_url"], "run-1")
        posted = calls[-1]
        self.assertEqual(posted[:4], ("gh", "api", "-X", "POST"))
        self.assertIn("repos/fork/repo/statuses/main-sha", posted)
        for part in ("state=success", "context=ctx", "target_url=run-1"):
            self.assertIn(part, posted)
        closer.assert_called_once_with("main")

    def test_failing_issue_close_keeps_the_reuse(self):
        found, _, closer = self.reuse(self.api([{"workflow_run": {"id": 1}}], self.RUNS[1]),
                                      close_error=subprocess.CalledProcessError(1, "gh"))
        self.assertEqual(found["html_url"], "run-1")
        closer.assert_called_once_with("main")

    def test_no_artifact_or_api_error_posts_nothing(self):
        for responses in (self.api([], {}), lambda cmd: subprocess.CalledProcessError(1, cmd),
                          lambda cmd: "not json", lambda cmd: json.dumps({})):
            with self.subTest(responses=responses):
                found, calls, closer = self.reuse(responses)
                self.assertIsNone(found)
                self.assertFalse([c for c in calls if "POST" in c])
                closer.assert_not_called()

    def test_failing_status_post_means_no_reuse(self):
        base = self.api([{"workflow_run": {"id": 1}}], self.RUNS[1])
        found, _, closer = self.reuse(lambda cmd: subprocess.CalledProcessError(1, cmd) if "POST" in cmd else base(cmd))
        self.assertIsNone(found)
        closer.assert_not_called()


class ReplayTests(unittest.TestCase):
    def scenario(self, column_zero=False, conflict=None, later_conflict=False, fix=None):
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
            (root / "second").write_text("base\n")
            commit("base")
            base = git("rev-parse", "HEAD")
            catalog({"a": {}, "ours": {}, "z": {}})
            if conflict == "other":
                (root / "other").write_text("ours\n")
                if fix == "partial":
                    (root / "second").write_text("ours\n")
            commit("ours")
            (root / "clean").write_text("clean cherry-pick result\n")
            git("add", "clean")
            git("commit", "--amend", "--no-edit", "-q")
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
            (root / "second").write_text("upstream\n")
            commit("upstream")
            upstream = git("rev-parse", "HEAD")
            git("update-ref", "refs/remotes/upstream/main", upstream)
            git("checkout", "-q", "--detach", ours)
            if fix:
                path = root / "notchcast/replay-fixes/ours.patch"
                path.parent.mkdir(parents=True)
                valid = "diff --git a/other b/other\n--- a/other\n+++ b/other\n@@ -1 +1,2 @@\n upstream\n+ours\n"
                if fix == "labelled":
                    # A fix for another base first, then the one for this base under a label.
                    path.write_text(valid.replace(" upstream\n", " newer upstream\n"))
                    path.with_name("ours.v1-0-0-beta-1.patch").write_text(valid)
                    path.with_name("ours-longer.v1.patch").write_text("invalid patch\n")
                else:
                    path.write_text(valid if fix in {"valid", "partial", "extra"} else "invalid patch\n")
                if fix == "extra":
                    with path.open("a") as stream:
                        stream.write("diff --git a/clean b/clean\n--- a/clean\n+++ b/clean\n"
                                     "@@ -1 +1 @@\n-clean cherry-pick result\n+changed\n")
                commit("stored fix")
            if (conflict or later_conflict) and fix not in {"valid", "labelled"}:
                with self.assertRaises(CI.Conflict) as caught:
                    CI.replay(root, upstream, check=True)
                self.assertEqual(caught.exception.subject, "later conflict" if later_conflict else "ours")
                self.assertEqual(caught.exception.files,
                                 ["other", "second"] if fix == "partial" else
                                 ["other"] if later_conflict or conflict == "other" else [CATALOG])
            else:
                CI.replay(root, upstream, check=True)
                self.assertEqual(set(json.loads((root / CATALOG).read_text())["strings"]),
                                 {"a", "ours", "upstream", "z"})
                self.assertEqual(git("diff", "--name-only", "--diff-filter=U"), "")
                self.assertEqual((root / "clean").read_text(), "clean cherry-pick result\n")
                if fix in {"valid", "labelled"}:
                    self.assertEqual((root / "other").read_text(), "upstream\nours\n")

    def test_per_file_fix_preserves_clean_results_and_catalog(self):
        self.scenario(conflict="other", fix="valid")

    def test_fix_labelled_for_another_base_applies_when_the_bare_fix_does_not(self):
        self.scenario(conflict="other", fix="labelled")

    def test_invalid_fix_raises_conflict(self):
        self.scenario(conflict="other", fix="invalid")

    def test_fix_missing_conflicting_file_raises_conflict(self):
        self.scenario(conflict="other", fix="partial")

    def test_fix_touching_clean_file_raises_conflict(self):
        self.scenario(conflict="other", fix="extra")

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

    def test_pruned_paths_stay_gone_without_conflict(self):
        """Our generated commit removes website/; upstream keeps editing it. The replay never picks that removal,
        so it cannot conflict, and regenerate removes the path again."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            def write(path, text):
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_text(text)
            def commit(message):
                git("add", "-A")
                git("commit", "-qm", message)
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("config", "core.hooksPath", "/dev/null")
            write("README.md", "upstream readme\n")
            write("website/page.md", "base\n")
            write("website/package-lock.json", "{}\n")
            write("project.yml", "name: Tinycast\n")
            write(CI.PBXPROJ, "project\n")
            write(CI.SCHEME, "scheme\n")
            write(CI.RUNTIME_JS, "runtime\n")
            write("docs/screenshot.png", "png\n")
            write("docs/development.md", "kept\n")
            write("Scripts/gen-emoji.js", "generator\n")
            write("Scripts/lint.sh", "kept\n")
            commit("base")
            base = git("rev-parse", "HEAD")
            write("notchcast/README.public.md", "ours\n")
            write("notchcast/prune-paths.txt",
                  "# one path per line\n\nwebsite/\ndocs/screenshot.png\nREADME.upstream.md\nScripts/gen-emoji.js\n")
            write("feature.swift", "ours\n")
            write("README.upstream.md", "made by the old regenerate\n")
            commit("ours")
            CI.regenerate(root, base)
            git("add", "-A", "--", *CI.GENERATED)
            git("commit", "-qm", CI.GENERATED_COMMIT)
            self.assertFalse((root / "website").exists())
            self.assertEqual(git("ls-files", "README.upstream.md", "docs/screenshot.png", "Scripts/gen-emoji.js"), "")
            self.assertEqual(git("ls-files", "docs", "Scripts"), "Scripts/lint.sh\ndocs/development.md")
            ours = git("rev-parse", "HEAD")
            git("checkout", "-q", "--detach", base)
            write("website/page.md", "upstream edit\n")
            write("website/new.md", "new page\n")
            commit("upstream edits the website")
            upstream = git("rev-parse", "HEAD")
            git("update-ref", "refs/remotes/upstream/main", upstream)
            git("checkout", "-q", "--detach", ours)
            CI.replay(root, upstream)
            self.assertEqual(git("log", "-1", "--format=%s"), CI.GENERATED_COMMIT)
            self.assertEqual(git("ls-files", "website"), "")
            self.assertFalse((root / "website").exists())
            self.assertEqual(git("status", "--porcelain"), "")
            self.assertEqual((root / "feature.swift").read_text(), "ours\n")
            self.assertEqual(git("ls-files", "README.upstream.md", "docs/screenshot.png", "Scripts/gen-emoji.js"), "")
            # A second regenerate on the result is a no-op: nothing left to prune.
            CI.regenerate(root, upstream)
            self.assertEqual(git("status", "--porcelain"), "")

    def test_prune_list_never_covers_kept_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "notchcast").mkdir()
            (root / "docs/features").mkdir(parents=True)
            for path in ("LICENSE", "NOTICE.md", "AGENTS.md", "docs/", "docs/features", "docs/ui.md", "Tests/",
                         "Tests/nc-x-test.swift", "Scripts/", "Scripts/raycast-runtime/build.mjs", "/", "."):
                (root / "notchcast/prune-paths.txt").write_text(path + "\n")
                with self.assertRaises(SystemExit, msg=path):
                    CI.pruned(root)
            (root / "notchcast/prune-paths.txt").write_text("docs/screenshot.png\nScripts/gen-emoji.js\n")
            self.assertEqual(CI.pruned(root), ["docs/screenshot.png", "Scripts/gen-emoji.js"])
        # The fork's own list passes.
        CI.pruned(Path(__file__).resolve().parent.parent)


if __name__ == "__main__":
    unittest.main(verbosity=2)
