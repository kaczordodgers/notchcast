#!/usr/bin/env python3
import json
import runpy
from pathlib import Path

route = runpy.run_path(str(Path(__file__).with_name("route.py")))["route"]
NOW = 1_000_000
OWNER = {"ACTOR": "owner", "OWNER": "owner", "REPO": "owner/repo"}


def run(count, variables, **env):
    return route({**OWNER, "COUNT": str(count), "VARS": json.dumps(variables), **env}, NOW)


fresh = {"NOTCHCAST_IDLE_MBP": f"2 {NOW - 30}", "NOTCHCAST_IDLE_MBA": f"1 {NOW - 200}", "LANDING_HOLD": "7 9 auto"}
assert run(4, fresh, EVENT="push") == ["notchcast-mac"] * 3 + ["xcode-27"]
assert run(2, fresh, EVENT="workflow_dispatch") == ["notchcast-mac"] * 2
assert run(0, fresh, EVENT="push") == []
print("PASS: idle Macs first, hosted for the rest")

stale = {"NOTCHCAST_IDLE_MBP": f"2 {NOW - 301}", "NOTCHCAST_IDLE_MBA": "soon", "NOTCHCAST_IDLE_X": f"-1 {NOW}"}
assert run(2, stale, EVENT="push") == ["xcode-27"] * 2
assert route({**OWNER, "COUNT": "1", "VARS": "not json", "EVENT": "push"}, NOW) == ["xcode-27"]
print("PASS: a stale, malformed or missing idle count is no Mac")

same = {"EVENT": "pull_request", "HEAD_REPO": "owner/repo"}
assert run(1, fresh, **same, ACTION="ready_for_review") == ["notchcast-mac"]
assert run(1, fresh, **same, ACTION="synchronize") == ["xcode-27"]
assert run(1, fresh, **same, ACTION="opened", ELIGIBLE="false") == ["xcode-27"]
assert run(1, fresh, EVENT="pull_request", HEAD_REPO="fork/repo", ACTION="opened") == ["xcode-27"]
assert run(1, fresh, EVENT="pull_request_target", HEAD_REPO="owner/repo") == ["xcode-27"]
assert run(1, fresh, EVENT="push", ACTOR="someone") == ["xcode-27"]
assert route({"COUNT": "1", "VARS": json.dumps(fresh), "EVENT": "push"}, NOW) == ["xcode-27"]
print("PASS: only the owner's own refs reach a Mac")
