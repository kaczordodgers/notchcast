#!/usr/bin/env python3
import runpy
from pathlib import Path

module = runpy.run_path(str(Path(__file__).with_name("route.py")))
route, decide, hosted_busy = module["route"], module["decide"], module["hosted_busy"]
NOW = 1_000_000
OWNER = {"ACTOR": "owner", "OWNER": "owner", "REPO": "owner/repo"}


def run(count, idle, **env):
    return route({**OWNER, "COUNT": str(count), "IDLE": "\n".join(idle), **env}, NOW)


fresh = [f"2 {NOW - 30}", f"1 {NOW - 150}"]
assert run(4, fresh, EVENT="push") == ["notchcast-mac"] * 3 + ["xcode-27"]
assert run(2, fresh, EVENT="workflow_dispatch") == ["notchcast-mac"] * 2
assert run(0, fresh, EVENT="push") == []
print("PASS: idle Macs first, hosted for the rest")

stale = [f"2 {NOW - 151}", "", "soon", f"-1 {NOW}", f"many {NOW}", f"1.5 {NOW}", f"1 {NOW} auto", f"1 {NOW + 61}"]
assert run(2, stale, EVENT="push") == ["xcode-27"] * 2
assert route({**OWNER, "COUNT": "1", "EVENT": "push"}, NOW) == ["xcode-27"]
assert run("many", fresh, EVENT="push") == []
print("PASS: a stale, malformed or missing idle count is no Mac")

same = {"EVENT": "pull_request", "HEAD_REPO": "owner/repo"}
assert run(1, fresh, **same, ACTION="ready_for_review") == ["notchcast-mac"]
assert run(1, fresh, **same, ACTION="synchronize") == ["xcode-27"]
assert run(1, fresh, **same, ACTION="opened", ELIGIBLE="false") == ["xcode-27"]
assert run(1, fresh, EVENT="pull_request", HEAD_REPO="fork/repo", ACTION="opened") == ["xcode-27"]
assert run(1, fresh, EVENT="pull_request_target", HEAD_REPO="owner/repo") == ["xcode-27"]
assert run(1, fresh, EVENT="push", ACTOR="someone") == ["xcode-27"]
assert route({"COUNT": "1", "IDLE": "\n".join(fresh), "EVENT": "push"}, NOW) == ["xcode-27"]
print("PASS: only the owner's own refs reach a Mac")


def pool(count, idle, busy, **env):
    return route({**OWNER, "COUNT": str(count), "IDLE": "\n".join(idle), "EVENT": "push", **env}, NOW, busy)


assert pool(2, fresh, 0) == ["notchcast-mac"] * 2
assert pool(4, fresh, 0) == ["notchcast-mac"] * 3 + ["xcode-27"]
assert pool(3, [], 0) == ["xcode-27"] * 3
assert pool(3, [], 2) == ["xcode-27"] * 3
assert pool(4, [], 3) == ["xcode-27"] * 2 + ["notchcast-mac"] * 2
assert pool(2, [], 5) == ["notchcast-mac"] * 2
assert pool(2, [], 9) == ["notchcast-mac"] * 2
assert pool(3, [f"1 {NOW}"], 4) == ["notchcast-mac", "xcode-27", "notchcast-mac"]
assert pool(3, [f"1 {NOW}"], 0) == ["notchcast-mac", "xcode-27", "xcode-27"]
assert pool(2, [], None) == ["xcode-27"] * 2
assert pool(2, fresh, 0, ELIGIBLE="false") == ["xcode-27"] * 2
assert pool(1, fresh, 0, EVENT="pull_request", HEAD_REPO="owner/repo", ACTION="ready_for_review") == ["notchcast-mac"]
assert pool(1, fresh, 0, EVENT="pull_request", HEAD_REPO="owner/repo", ACTION="synchronize") == ["xcode-27"]
print("PASS: pool first, hosted while a slot is free, pool when both are full")


def api(queued, active, jobs):
    def fetch(path):
        if "/actions/runs?" in path:
            status = path.split("status=")[1].split("&")[0]
            return {"workflow_runs": [{"id": run} for run in (queued if status == "queued" else active)]}
        return {"jobs": jobs[int(path.split("/runs/")[1].split("/")[0])]}

    return fetch


def failing(path):
    raise OSError("api down")


jobs = {
    1: [
        {"status": "queued", "labels": ["xcode-27"]},
        {"status": "in_progress", "labels": ["macos-latest"]},
        {"status": "completed", "labels": ["xcode-27"]},
        {"status": "queued", "labels": ["notchcast-mac"]},
        {"status": "queued", "labels": ["ubuntu-latest"]},
    ],
    2: [{"status": "in_progress", "labels": ["macos-14"]}],
}
assert hosted_busy("owner/repo", api([1], [2], jobs)) == 3
assert hosted_busy("owner/repo", api([], [], jobs)) == 0
print("PASS: hosted count is queued or running macOS jobs on the hosted image")

assert decide({**OWNER, "COUNT": "2", "IDLE": "\n".join(fresh), "EVENT": "push"}, NOW, failing) == ["notchcast-mac"] * 2
assert decide({**OWNER, "COUNT": "2", "IDLE": "", "EVENT": "push"}, NOW, failing) == ["xcode-27"] * 2
assert decide({**OWNER, "COUNT": "2", "IDLE": "", "EVENT": "push"}, NOW, api([], [], jobs)) == ["xcode-27"] * 2
assert decide({**OWNER, "COUNT": "2", "IDLE": "", "EVENT": "push", "ACTOR": "someone"}, NOW, failing) == ["xcode-27"] * 2
assert decide({**OWNER, "COUNT": "0", "IDLE": "", "EVENT": "push"}, NOW, failing) == []
print("PASS: an API failure falls back to idle Macs first; no API call when no Mac may take a job")
