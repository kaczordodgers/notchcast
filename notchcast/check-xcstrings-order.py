#!/usr/bin/env python3
"""Check catalog key order and require Swift references or explicit exceptions for key changes."""

# Use notchcast/xcstrings-allowed-keys.json for intentional key changes without Swift references.
import argparse
import json
import re
import subprocess
import sys

CATALOG = "Tinycast/Resources/Localizable.xcstrings"


def git(*args):
    return subprocess.check_output(["git", *args], text=True)


def check(base, head, added_swift, remaining_swift, allowed=()):
    errors = []
    shared = base.keys() & head.keys()
    if [k for k in base if k in shared] != [k for k in head if k in shared]:
        errors.append("relative order of existing keys changed")
    for key in sorted(head.keys() - base.keys() - set(allowed)):
        if not referenced(key, added_swift):
            errors.append("added/restored key needs a changed Swift reference or entry in "
                          "notchcast/xcstrings-allowed-keys.json: " + key)
    for key in sorted(base.keys() - head.keys() - set(allowed)):
        if referenced(key, remaining_swift):
            errors.append("removed key still referenced in Swift: " + key)
    return errors


def referenced(key, swift):
    swift = re.sub(r'\\\n\s*', '', swift)
    swift = re.sub(r'"""\n[ \t]*(.*?)\n[ \t]*"""',
                   lambda match: '"' + match[1] + '"', swift, flags=re.S)
    key = key.replace('%%', '%')
    if json.dumps(key, ensure_ascii=False) in swift:
        return True
    parts = re.split(r'%(?:\d+\$)?(?:\.\d+)?(?:lld|llu|ld|lf|lu|d|f|u|@)', key)
    if len(parts) == 1:
        return False
    interpolation = r'\\\(.*?\)'
    pattern = interpolation.join(re.escape(json.dumps(p, ensure_ascii=False)[1:-1]) for p in parts)
    return re.search('"' + pattern + '"', swift) is not None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-ref", default="origin/main")
    parser.add_argument("--head", default="HEAD")
    args = parser.parse_args()
    base = git("merge-base", args.base_ref, args.head).strip()
    catalogs = [json.loads(git("show", ref + ":" + CATALOG))["strings"] for ref in (base, args.head)]
    diff = git("diff", "--unified=0", base, args.head, "--", "*.swift")
    added = "\n".join(line[1:] for line in diff.splitlines() if line.startswith("+") and not line.startswith("+++"))
    remaining = git("grep", "-h", "-e", "", args.head, "--", "Tinycast/**/*.swift")
    allow_path = "notchcast/xcstrings-allowed-keys.json"
    allowed = []
    if allow_path in git("ls-tree", "-r", "--name-only", args.head).splitlines():
        allowed = json.loads(git("show", args.head + ":" + allow_path))
    errors = check(*catalogs, added, remaining, allowed)
    for error in errors:
        print("xcstrings: " + error, file=sys.stderr)
    print(f"xcstrings: {len(catalogs[1].keys() - catalogs[0].keys())} added, "
          f"{len(catalogs[0].keys() - catalogs[1].keys())} removed; {len(errors)} errors")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
