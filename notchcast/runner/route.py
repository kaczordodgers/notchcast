#!/usr/bin/env python3
"""Print the runs-on label of each of COUNT macOS jobs: idle maintainer Macs first, then the hosted image."""
import json
import os
import time

HOSTED = "xcode-27"
MAC = "notchcast-mac"
# gate.sh rewrites its variable every 60 s, so one that missed two turns is a Mac that is asleep or offline.
FRESH = 150


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


def route(env, now):
    try:
        count = int(env.get("COUNT") or 0)
    except ValueError:
        count = 0
    # shortcut: runs planned within seconds can pick the same Mac and queue behind it; claim a runner if that hurts.
    macs = min(count, idle(env.get("IDLE") or "", now)) if takes_macs(env) else 0
    return [MAC] * macs + [HOSTED] * (count - macs)


if __name__ == "__main__":
    print(json.dumps(route(os.environ, int(time.time()))))
