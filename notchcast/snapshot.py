#!/usr/bin/env python3
"""Plan a main snapshot without changing any refs."""
import json
import os
from datetime import datetime, timezone

from ci import config, output, run, version_key


def plan(releases, main, commit, now):
    snapshots = [r for r in releases if not r["isDraft"] and ".snapshot." in r["tagName"]]
    if snapshots:
        latest = max(snapshots, key=lambda r: r["publishedAt"])
        if commit(latest["tagName"]) == main:
            return None
        published = datetime.fromisoformat(latest["publishedAt"].replace("Z", "+00:00"))
        if (now - published).total_seconds() < 3600:
            return None
    mirrors = [r["tagName"] for r in releases if not r["isDraft"] and version_key(r["tagName"])]
    base = max(mirrors, key=version_key)
    revision = now.strftime("%Y%m%d%H%M%S")
    return f"{base}.snapshot.{revision}"


if __name__ == "__main__":
    repo = config()["FORK_REPO"]
    now = datetime.now(timezone.utc)
    runs = json.loads(run("gh", "api", f"repos/{repo}/actions/workflows/snapshot.yml/runs?per_page=100"))["workflow_runs"]
    recent = [r for r in runs if str(r["id"]) != os.environ["GITHUB_RUN_ID"]
              and r["status"] != "queued"
              and (now - datetime.fromisoformat(r["run_started_at"].replace("Z", "+00:00"))).total_seconds() < 3600]
    if recent:
        print("Snapshot skipped: another attempt started within the last hour")
    else:
        pages = json.loads(run("gh", "api", "--paginate", "--slurp", f"repos/{repo}/releases?per_page=100"))
        releases = [{"tagName": r["tag_name"], "isDraft": r["draft"], "publishedAt": r["published_at"]}
                    for page in pages for r in page]
        main = run("git", "rev-parse", "HEAD")
        tag = plan(releases, main, lambda t: run("git", "rev-parse", f"refs/tags/{t}^{{commit}}"), now)
        if tag:
            output(tag=tag, version=tag[1:], build=os.environ["GITHUB_RUN_NUMBER"], main=main)
        else:
            print("Snapshot skipped: unchanged main or last publication less than an hour ago")
