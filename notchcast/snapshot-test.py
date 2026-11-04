#!/usr/bin/env python3
"""Pure snapshot checks: no network or installation."""
import json
import re
import runpy
import subprocess
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

from ci import release_tags, version_key
from snapshot import plan


class SnapshotTests(unittest.TestCase):
    def test_vkey(self):
        source = Path(__file__).with_name("update.sh").read_text()
        vkey = re.search(r"VKEY='(.*?)'", source, re.S)[1]
        tags = ["v0.12.7-beta.131", "v0.12.7-beta.131.snapshot.20261104090000",
                "v0.12.7-beta.131.snapshot.20261104100000", "v0.12.7-beta.132",
                "v0.12.7", "v0.12.7.snapshot.20261104110000", "v0.12.8-beta.1",
                "v0.13.0-beta.1", "v1.0.0"]
        result = subprocess.run(["jq", "-nc", "--argjson", "tags", json.dumps(tags),
                                 vkey + " $tags | reverse | sort_by(vkey)"],
                                check=True, capture_output=True, text=True)
        self.assertEqual(json.loads(result.stdout), tags)
        print("vkey: mirror < snapshot 1 < snapshot 2 < next beta < stable < stable snapshot < next patch beta < next minor < next major")

    def test_mirror_parser(self):
        self.assertIsNone(version_key("v0.12.7-beta.131.snapshot.20261104090000"))
        self.assertLess(version_key("v0.12.7-beta.131"), version_key("v0.12.8-beta.1"))

    def test_plan(self):
        now = datetime(2026, 11, 4, 12, tzinfo=timezone.utc)
        releases = [dict(tagName="v0.12.7-beta.131", isDraft=False, publishedAt="2026-11-01T00:00:00Z")]
        tag = "v0.12.7-beta.131.snapshot.20261104100000"
        self.assertEqual(plan(releases, "new", lambda _: "old", now),
                         "v0.12.7-beta.131.snapshot.20261104120000")
        releases.append(dict(tagName=tag, isDraft=False, publishedAt=(now - timedelta(hours=2)).isoformat()))
        self.assertIsNone(plan(releases, "old", lambda _: "old", now))
        self.assertIsNotNone(plan(releases, "new", lambda _: "old", now))
        releases[-1]["tagName"] = "v0.12.7-beta.131.snapshot.20261104113000"
        self.assertIsNone(plan(releases, "new", lambda _: "old", now))

    def test_hourly_after_slow_publication(self):
        releases = [dict(tagName="v0.12.7-beta.131", isDraft=False),
                    dict(tagName="v0.12.7-beta.131.snapshot.20261104110000", isDraft=False,
                         publishedAt="2026-11-04T11:25:00Z")]
        now = datetime(2026, 11, 4, 12, tzinfo=timezone.utc)
        self.assertIsNotNone(plan(releases, "new", lambda _: "old", now))
        self.assertIsNotNone(plan(releases, "new", lambda _: "old", now - timedelta(minutes=10)))
        self.assertIsNone(plan(releases, "new", lambda _: "old", now - timedelta(minutes=11)))

    def test_dispatch_after_failed_attempt(self):
        calls = []

        def run(*args):
            calls.append(args)
            if args[:2] == ("gh", "api"):
                self.assertNotIn("actions/workflows", " ".join(args))
                return json.dumps([[dict(tag_name="v0.12.7-beta.131", draft=False,
                                         published_at="2026-11-01T00:00:00Z")]])
            return "new"

        with patch("ci.run", side_effect=run), patch("ci.output") as output, \
                patch("ci.config", return_value={"FORK_REPO": "owner/repo"}), \
                patch.dict("os.environ", {"GITHUB_RUN_NUMBER": "42"}):
            runpy.run_path(str(Path(__file__).with_name("snapshot.py")), run_name="__main__")
        self.assertEqual(output.call_args.kwargs["main"], "new")
        self.assertEqual(len(calls), 2)

    def test_mirrors_survive_snapshot_pages(self):
        pages = [[dict(tag_name=f"v0.12.7.snapshot.{n}") for n in range(100)],
                 [dict(tag_name="v0.12.7-beta.131")]]
        with patch("ci.run", return_value=json.dumps(pages)) as run:
            self.assertIn("v0.12.7-beta.131", release_tags("owner/repo"))
        run.assert_called_once_with("gh", "api", "--paginate", "--slurp",
                                    "repos/owner/repo/releases?per_page=100")


if __name__ == "__main__":
    unittest.main()
