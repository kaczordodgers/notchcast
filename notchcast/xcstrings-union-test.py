#!/usr/bin/env python3
"""Checks for notchcast/xcstrings-union.py. Run: python3 notchcast/xcstrings-union-test.py (from the repo root)."""
import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("xcstrings_union", os.path.join(HERE, "xcstrings-union.py"))
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
failures = 0


def expect(condition, label):
    global failures
    if not condition:
        failures += 1
    print(("ok   " if condition else "FAIL ") + label)


def catalog(strings):
    return tool.dump({"sourceLanguage": "en", "strings": strings, "version": "1.0"}) + "\n"


def entry(text):
    return {"localizations": {"de": {"stringUnit": {"state": "translated", "value": text}}}}


# Upstream's real catalog round-trips byte for byte (Xcode layout, including empty objects).
upstream = subprocess.run(["git", "show", "upstream/main:" + tool.CATALOG], capture_output=True, text=True)
if upstream.returncode == 0:
    text, differing = tool.union(upstream.stdout, upstream.stdout)
    expect(text == upstream.stdout and not differing, "upstream catalog round-trips unchanged")
else:
    print("skip upstream round-trip (git fetch upstream first)")

base = {"Alpha": entry("A"), "Delta": entry("D"), "": {}}
ours = catalog({**base, "Bravo": entry("B")})
theirs = catalog({**base, "charlie": entry("C"), "Echo": entry("E")})
text, differing = tool.union(ours, theirs)
keys = list(json.loads(text)["strings"])
expect(keys == ["Alpha", "Delta", "", "Bravo", "charlie", "Echo"], "both sides' new keys are kept, ours first")
expect(keys.index("charlie") > keys.index("Bravo") and keys.index("Echo") > keys.index("Delta"),
       "new keys land after the last key sorting before them")
expect(not differing, "no differing keys reported for disjoint additions")
expect('"" : {\n\n    }' in text, "empty objects keep Xcode's layout")

text, differing = tool.union(catalog({"Alpha": entry("ours")}), catalog({"Alpha": entry("theirs")}))
expect(json.loads(text)["strings"]["Alpha"] == entry("ours") and differing == ["Alpha"],
       "a key changed on both sides keeps the first and is reported")

text, _ = tool.union(catalog({"Zulu": entry("Z")}), catalog({"alpha": entry("a")}))
expect(list(json.loads(text)["strings"]) == ["alpha", "Zulu"], "a key sorting first goes to the front")

sys.exit(1 if failures else 0)
