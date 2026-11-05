#!/usr/bin/env python3
"""Plan a main snapshot without changing any refs."""
import json
import os
import math
import time
from datetime import datetime, timedelta, timezone

from ci import config, output, run, version_key


def plan(releases, main, commit, now, event):
    snapshots = [r for r in releases if not r["isDraft"] and ".snapshot." in r["tagName"]]
    if snapshots:
        latest = max(snapshots, key=lambda r: r["tagName"].rsplit(".snapshot.", 1)[1])
        if commit(latest["tagName"]) == main:
            return {"error" if event == "workflow_dispatch" else "skip": f"unchanged main {main}"}
        revision = latest["tagName"].rsplit(".snapshot.", 1)[1]
        started = datetime.strptime(revision, "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc)
        opens = started + timedelta(minutes=50)
        if now < opens:
            reason = f"50-minute gate closed for main {main}; opens {opens:%Y-%m-%d %H:%M:%S} UTC"
            if event == "workflow_dispatch":
                return {"error": reason}
            return {"wait": math.ceil((opens - now).total_seconds())}
    mirrors = [r["tagName"] for r in releases if not r["isDraft"] and version_key(r["tagName"])]
    base = max(mirrors, key=version_key)
    revision = now.strftime("%Y%m%d%H%M%S")
    return {"tag": f"{base}.snapshot.{revision}"}


def main():
    repo = config()["FORK_REPO"]
    while True:
        run("git", "fetch", "--force", "--tags", "origin", "main")
        sha = run("git", "rev-parse", "FETCH_HEAD")
        pages = json.loads(run("gh", "api", "--paginate", "--slurp", f"repos/{repo}/releases?per_page=100"))
        releases = [{"tagName": r["tag_name"], "isDraft": r["draft"]} for page in pages for r in page]
        result = plan(releases, sha, lambda t: run("git", "rev-parse", f"refs/tags/{t}^{{commit}}"),
                      datetime.now(timezone.utc), os.environ["GITHUB_EVENT_NAME"])
        if "wait" in result:
            print(f"Waiting {result['wait']} seconds for the snapshot gate", flush=True)
            time.sleep(result["wait"])
            continue
        if "error" in result:
            print(f"::error::Snapshot skipped: {result['error']}")
            return 1
        if "skip" in result:
            print(f"Snapshot skipped: {result['skip']}")
            return 0
        tag = result["tag"]
        output(tag=tag, version=tag[1:], build=os.environ["GITHUB_RUN_NUMBER"], main=sha)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
