#!/usr/bin/env python3
"""Resolve a Localizable.xcstrings conflict between parallel branches by taking the union of their strings.

Usage:
  notchcast/xcstrings-union.py OURS THEIRS OUT   union of two catalog files, written to OUT
  notchcast/xcstrings-union.py --git             during a conflicted merge, rebase or cherry-pick: union of
                                                 HEAD's and the incoming commit's catalog, written and staged

The first file's keys keep their order and values; keys only in later files are inserted after the last key
that sorts before them (case-insensitive). Output uses Xcode's own layout, so an unchanged catalog round-trips
byte for byte. A key present on both sides with different values keeps the first and is reported on stderr.
"""
import json
import subprocess
import sys

CATALOG = "Tinycast/Resources/Localizable.xcstrings"


def dump(value, depth=0):
    pad = "  " * depth
    if isinstance(value, dict):
        if not value:
            return "{\n\n" + pad + "}"
        items = [pad + "  " + json.dumps(k, ensure_ascii=False) + " : " + dump(v, depth + 1) for k, v in value.items()]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        if not value:
            return "[\n\n" + pad + "]"
        return "[\n" + ",\n".join(pad + "  " + dump(v, depth + 1) for v in value) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def union(first, *others):
    """The merged catalog text and the keys whose values differ between sides."""
    merged = json.loads(first)
    strings = merged["strings"]
    keys = list(strings)
    differing = []
    for text in others:
        for key, value in json.loads(text)["strings"].items():
            if key not in strings:
                strings[key] = value
                position = 0
                for index, existing in enumerate(keys):
                    if existing.casefold() <= key.casefold():
                        position = index + 1
                keys.insert(position, key)
            elif strings[key] != value:
                differing.append(key)
    merged["strings"] = {key: strings[key] for key in keys}
    return dump(merged) + "\n", differing


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def incoming_ref():
    for ref in ("MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD"):
        if subprocess.run(["git", "rev-parse", "-q", "--verify", ref], capture_output=True).returncode == 0:
            return ref
    sys.exit("xcstrings-union: no merge, rebase or cherry-pick in progress")


def main(argv):
    if argv == ["--git"]:
        root = git("rev-parse", "--show-toplevel").strip()
        text, differing = union(git("show", "HEAD:" + CATALOG), git("show", incoming_ref() + ":" + CATALOG))
        with open(root + "/" + CATALOG, "w") as file:
            file.write(text)
        git("-C", root, "add", "--", CATALOG)
    elif len(argv) == 3:
        ours, theirs, out = argv
        text, differing = union(open(ours).read(), open(theirs).read())
        open(out, "w").write(text)
    else:
        sys.exit(__doc__)
    for key in differing:
        print("xcstrings-union: kept the first side's value for " + json.dumps(key, ensure_ascii=False), file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
