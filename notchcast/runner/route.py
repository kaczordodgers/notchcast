#!/usr/bin/env python3
"""Print the runs-on label of each of COUNT macOS jobs: the maintainer Mac pool or the hosted image."""
import json
import os
import sys
import time
import urllib.request

HOSTED = "xcode-27"
MAC = "notchcast-mac"
HOSTED_SLOTS = 5
# gate.sh rewrites its variable every 60 s, so one that missed two turns is a Mac that is asleep or offline.
FRESH = 150
ACTIVE = ("queued", "in_progress")


def takes_macs(env):
    if not env.get("OWNER") or env.get("ACTOR") != env.get("OWNER") or env.get("ELIGIBLE", "true") != "true":
        return False
    if env.get("EVENT") in ("push", "workflow_dispatch"):
        return True
    # A synchronize arrives with a push, and that push's Main harnesses run is the one that takes the Macs.
    return (
        env.get("EVENT") == "pull_request"
        and env.get("HEAD_REPO") == env.get("REPO")
        and env.get("ACTION") != "synchronize"
    )


def count_of(env):
    try:
        return int(env.get("COUNT") or 0)
    except ValueError:
        return 0


def idle(lines, now):
    total = 0
    for line in lines.splitlines():
        try:
            count, stamp = (int(part) for part in line.split())
        except ValueError:
            continue
        if -60 <= now - stamp <= FRESH:
            total += max(count, 0)
    return total


def hosted(label):
    return label == HOSTED or label.startswith("macos-")


def hosted_busy(repo, fetch):
    """Queued or running macOS jobs of this repository on the hosted image."""
    busy = 0
    for status in ACTIVE:
        for run in fetch(f"/repos/{repo}/actions/runs?status={status}&per_page=100")["workflow_runs"]:
            for job in fetch(f"/repos/{repo}/actions/runs/{run['id']}/jobs?filter=latest&per_page=100")["jobs"]:
                if job["status"] in ACTIVE and any(hosted(label) for label in job["labels"]):
                    busy += 1
    return busy


def route(env, now, busy=None):
    """Labels for COUNT jobs. busy is the hosted count, or None when the API could not say."""
    count = count_of(env)
    if not takes_macs(env):
        return [HOSTED] * count
    pool = idle(env.get("IDLE") or "", now)
    if busy is None:
        # shortcut: without the hosted count, today's rule: idle Macs first, the hosted image for the rest.
        macs = min(count, pool)
        return [MAC] * macs + [HOSTED] * (count - macs)
    # Hosted only while an idle Mac is not waiting for the job and a hosted slot is free.
    free = max(HOSTED_SLOTS - busy, 0)
    labels = []
    for _ in range(count):
        if pool == 0 and free > 0:
            labels.append(HOSTED)
            free -= 1
        else:
            labels.append(MAC)
            pool = max(pool - 1, 0)
    return labels


def decide(env, now, fetch):
    busy = None
    if takes_macs(env) and count_of(env) > 0:
        try:
            busy = hosted_busy(env.get("REPO", ""), fetch)
        except Exception as error:
            print(f"route: hosted count unavailable, idle Macs first ({error})", file=sys.stderr)
    labels = route(env, now, busy)
    print(f"route: hosted busy {busy}, idle Macs {idle(env.get('IDLE') or '', now)} -> {labels}", file=sys.stderr)
    return labels


def github(env):
    base = env.get("GITHUB_API_URL", "https://api.github.com")
    token = env.get("GITHUB_TOKEN", "")

    def fetch(path):
        if not token:
            raise RuntimeError("no GITHUB_TOKEN")
        request = urllib.request.Request(base + path, headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        })
        with urllib.request.urlopen(request, timeout=20) as reply:
            return json.load(reply)

    return fetch


if __name__ == "__main__":
    print(json.dumps(decide(os.environ, int(time.time()), github(os.environ))))
