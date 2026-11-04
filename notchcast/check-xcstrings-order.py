#!/usr/bin/env python3
"""Check catalog key order and require Swift references or explicit exceptions for key changes."""

# Use notchcast/xcstrings-allowed-keys.json for intentional key changes without Swift references.
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
import runpy

CATALOG = "Tinycast/Resources/Localizable.xcstrings"


def git(*args):
    return subprocess.check_output(["git", "-C", str(Path.cwd()), *args], text=True)


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
    union = runpy.run_path(str(Path(__file__).with_name('xcstrings-union.py')))
    tables = [CATALOG, 'Tinycast/Resources/Notchcast.xcstrings']
    catalogs = [{table: json.loads(union['git_catalog'](ref, table))['strings']
                 for table in tables} for ref in (base, args.head)]
    diff = git("diff", "--unified=0", base, args.head, "--", "*.swift")
    added = "\n".join(line[1:] for line in diff.splitlines() if line.startswith("+") and not line.startswith("+++"))
    remaining = git("grep", "-h", "-e", "", args.head, "--", "Tinycast/**/*.swift")
    allow_path = "notchcast/xcstrings-allowed-keys.json"
    allowed = []
    if allow_path in git("ls-tree", "-r", "--name-only", args.head).splitlines():
        allowed = json.loads(git("show", args.head + ":" + allow_path))
    errors = []
    migration = not catalogs[0][tables[1]] and bool(catalogs[1][tables[1]])
    for table in tables:
        old, new = [catalog[table] for catalog in catalogs]
        moved = set().union(*(catalog[other].keys() for catalog in catalogs for other in tables
                              if other != table))
        if migration and table == CATALOG:
            old = {key: old[key] for key in new if key in old} | {
                key: value for key, value in old.items() if key not in new}
        errors += check(old, new, added, remaining, set(allowed) | moved)
    if catalogs[1][tables[1]]:
        errors += runpy.run_path(str(Path(__file__).with_name('check-fork-strings.py')))['check']()
        if subprocess.run(['node', str(Path(__file__).with_name('check-localizations.js'))]).returncode:
            errors.append('fork catalog translation validation failed')
    for error in errors:
        print("xcstrings: " + error, file=sys.stderr)
    print(f"xcstrings: checked both tables; {len(errors)} errors")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
