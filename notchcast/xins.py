#!/usr/bin/env python3
"""xins.py TARGET SOURCE BASE: insert keys that SOURCE adds over BASE into TARGET as text, touching no other line."""
import json
import re
import runpy
import sys

dump = runpy.run_path("notchcast/xcstrings-union.py")["dump"]

target, source, base = sys.argv[1:4]
src = json.load(open(source))["strings"]
old = json.load(open(base))["strings"]
lines = open(target).read().split("\n")
have = json.loads("\n".join(lines))["strings"]
new = [k for k in src if k not in old and k not in have]
for key in new:
    tops = [(i, json.loads(m.group(1))) for i, l in enumerate(lines) if (m := re.match(r'^    ("(?:[^"\\]|\\.)*") : ', l))]
    after = [i for i, k in tops if k.casefold() > key.casefold()]
    block = ("    " + json.dumps(key, ensure_ascii=False) + " : " + dump(src[key], 2)).split("\n")
    if after:
        at = after[0]
        lines[at:at] = block[:-1] + [block[-1] + ","]
    else:
        end = max(i for i, l in enumerate(lines) if l == "  },")
        lines[end - 1] += ","
        lines[end:end] = block
json.loads("\n".join(lines))
open(target, "w").write("\n".join(lines))
print(len(new), "inserted")
