#!/usr/bin/env python3
"""Snapshot planning and manual-run failure checks."""
import contextlib
import importlib.util
from importlib.machinery import SourceFileLoader
import io
import json
import os
import re
import subprocess
from pathlib import Path
import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from ci import release_tags, version_key

source = os.environ.get("SNAPSHOT_MODULE", str(Path(__file__).with_name("snapshot.py")))
spec = importlib.util.spec_from_loader("snapshot", SourceFileLoader("snapshot", source))
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)


class SnapshotTests(unittest.TestCase):
    def test_workflow_holds_snapshot_lock_through_publish(self):
        root = Path(__file__).resolve().parent.parent
        revision = os.environ.get("SNAPSHOT_WORKFLOW_REF")
        workflow = (subprocess.check_output(
            ["git", "show", f"{revision}:.github/workflows/snapshot.yml"], cwd=root, text=True)
            if revision else (root / ".github/workflows/snapshot.yml").read_text())
        header, jobs = workflow.split("\njobs:\n", 1)
        self.assertEqual(len(re.findall(r"^\s*concurrency:", workflow, re.M)), 1)
        self.assertIn("\nconcurrency:\n  group: snapshot\n  cancel-in-progress: false\n", header + "\n")
        self.assertNotRegex(jobs, r"(?m)^\s+concurrency:")
        sections = dict(re.findall(r"^  (\w+):\n(.*?)(?=^  \w+:\n|\Z)", jobs, re.M | re.S))
        self.assertNotIn("check", sections)
        self.assertLess(sections["plan"].index("run: python3 notchcast/snapshot-test.py"),
                        sections["plan"].index("run: python3 notchcast/snapshot.py"))
        self.assertIn("    runs-on: ubuntu-latest\n", sections["plan"])
        self.assertIn('cron: "7,27,47 * * * *"', header)
        self.assertNotIn("snapshot-test.py", (root / "notchcast/ci-tests.sh").read_text())

    def test_mirror_parser(self):
        self.assertIsNone(version_key("v0.12.7-beta.131.snapshot.20261104090000"))
        self.assertLess(version_key("v0.12.7-beta.131"), version_key("v0.12.8-beta.1"))

    def test_mirrors_survive_snapshot_pages(self):
        pages = [[dict(tag_name=f"v0.12.7.snapshot.{n}") for n in range(100)],
                 [dict(tag_name="v0.12.7-beta.131")]]
        with patch("ci.run", return_value=json.dumps(pages)) as run:
            self.assertIn("v0.12.7-beta.131", release_tags("owner/repo"))
        run.assert_called_once_with("gh", "api", "--paginate", "--slurp",
                                    "repos/owner/repo/releases?per_page=100")

    def test_first_snapshot_and_failed_attempt_do_not_block(self):
        result = snapshot.plan(self.releases[:1], "current-main", lambda tag: "old",
                               datetime(2026, 11, 5, 12, tzinfo=timezone.utc), "workflow_dispatch")
        self.assertEqual(result, {"tag": "v1.0.0.snapshot.20261105120000"})

    def test_publication_time_does_not_extend_gate(self):
        self.assertIn("tag", self.plan(minute=50))
        self.assertEqual(self.plan(minute=49), {"wait": 60})

    releases = [{"tagName": "v1.0.0", "isDraft": False},
                {"tagName": "v1.0.0.snapshot.20261105120000", "isDraft": False}]

    def plan(self, event="push", minute=30, commit="old", skip_gate=False):
        return snapshot.plan(self.releases, "current-main", lambda tag: commit,
                             datetime(2026, 11, 5, 12, minute, tzinfo=timezone.utc), event, skip_gate)

    def test_dispatch_gate_names_sha_and_open_time(self):
        result = self.plan("workflow_dispatch")
        self.assertIn("current-main", result["closed"])
        self.assertIn("2026-11-05 12:50:00 UTC", result["closed"])

    def test_skip_gate_only_bypasses_timer(self):
        self.assertIn("tag", self.plan("workflow_dispatch", skip_gate=True))
        self.assertEqual(self.plan("workflow_dispatch", commit="current-main", skip_gate=True),
                         {"error": "unchanged main current-main"})

    def test_dispatch_unchanged_is_error(self):
        self.assertEqual(self.plan("workflow_dispatch", commit="current-main"),
                         {"error": "unchanged main current-main"})

    def test_push_wait_seconds(self):
        self.assertEqual(self.plan(), {"wait": 1200})

    def test_gate_open_plans_tag(self):
        self.assertEqual(self.plan(minute=50), {"tag": "v1.0.0.snapshot.20261105125000"})

    def test_automatic_unchanged_skips_after_wait(self):
        self.assertEqual(self.plan(commit="current-main"), {"skip": "unchanged main current-main"})

    def run_main(self, event, commits):
        pages = json.dumps([[{"tag_name": r["tagName"], "draft": r["isDraft"]} for r in self.releases]])
        replies = []
        for commit in commits:
            replies.extend(["", "current-main", pages, commit])
        clock = unittest.mock.Mock()
        clock.now.return_value = datetime(2026, 11, 5, 12, 30, tzinfo=timezone.utc)
        stream = io.StringIO()
        with patch.dict(os.environ, GITHUB_EVENT_NAME=event, SKIP_GATE="false"), patch.object(snapshot, "run", side_effect=replies), \
                patch.object(snapshot, "datetime", clock), patch.object(snapshot.time, "sleep") as sleep, \
                contextlib.redirect_stdout(stream):
            clock.strptime = datetime.strptime
            status = snapshot.main()
        return status, stream.getvalue(), sleep

    def test_dispatch_gate_exits_green_with_notice(self):
        status, log, sleep = self.run_main("workflow_dispatch", ["old"])
        self.assertEqual(status, 0)
        self.assertIn("::notice::", log)
        self.assertIn("current-main", log)
        self.assertIn("2026-11-05 12:50:00 UTC", log)
        sleep.assert_not_called()

    def test_dispatch_unchanged_exits_red(self):
        status, log, sleep = self.run_main("workflow_dispatch", ["current-main"])
        self.assertEqual(status, 1)
        self.assertIn("::error::Snapshot skipped: unchanged main current-main", log)

    def test_wait_refreshes_then_skips_published_main(self):
        status, log, sleep = self.run_main("push", ["old", "current-main"])
        self.assertEqual(status, 0)
        sleep.assert_called_once_with(1200)
        self.assertIn("Snapshot skipped: unchanged main current-main", log)


if __name__ == "__main__":
    unittest.main()
