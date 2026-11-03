#!/usr/bin/env python3
"""Pure snapshot checks: no network or installation."""
import json
import re
import subprocess
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from ci import version_key
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
        tag = plan(releases, "new", lambda _: "old", now)
        self.assertEqual(tag, "v0.12.7-beta.131.snapshot.20261104120000")
        releases.append(dict(tagName=tag, isDraft=False, publishedAt=(now - timedelta(hours=2)).isoformat()))
        self.assertIsNone(plan(releases, "old", lambda _: "old", now))
        self.assertIsNotNone(plan(releases, "new", lambda _: "old", now))
        releases[-1]["publishedAt"] = (now - timedelta(minutes=30)).isoformat()
        self.assertIsNone(plan(releases, "new", lambda _: "old", now))


if __name__ == "__main__":
    unittest.main()
