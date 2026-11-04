#!/usr/bin/env python3
"""Plan a main snapshot without changing any refs."""
import json
import os
from datetime import datetime, timezone

from ci import config, output, run, version_key


def plan(releases, main, commit, now):
    snapshots = [r for r in releases if not r["isDraft"] and ".snapshot." in r["tagName"]]
    if snapshots:
        latest = max(snapshots, key=lambda r: r["tagName"].rsplit(".snapshot.", 1)[1])
        if commit(latest["tagName"]) == main:
            return None
        revision = latest["tagName"].rsplit(".snapshot.", 1)[1]
        started = datetime.strptime(revision, "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc)
        if (now - started).total_seconds() < 3000:
            return None
    mirrors = [r["tagName"] for r in releases if not r["isDraft"] and version_key(r["tagName"])]
    base = max(mirrors, key=version_key)
    revision = now.strftime("%Y%m%d%H%M%S")
    return f"{base}.snapshot.{revision}"


if __name__ == "__main__":
    repo = config()["FORK_REPO"]
    now = datetime.now(timezone.utc)
    pages = json.loads(run("gh", "api", "--paginate", "--slurp", f"repos/{repo}/releases?per_page=100"))
    releases = [{"tagName": r["tag_name"], "isDraft": r["draft"], "publishedAt": r["published_at"]}
                for page in pages for r in page]
    main = run("git", "rev-parse", "HEAD")
    tag = plan(releases, main, lambda t: run("git", "rev-parse", f"refs/tags/{t}^{{commit}}"), now)
    if tag:
        output(tag=tag, version=tag[1:], build=os.environ["GITHUB_RUN_NUMBER"], main=main)
    else:
        print("Snapshot skipped: unchanged main or last published snapshot started less than 50 minutes ago")
