#!/usr/bin/env python3
"""Three-way catalog merge: BASE MAIN BRANCH OUT, or --git [--main-ref origin/main]."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

CATALOG = "Tinycast/Resources/Localizable.xcstrings"


def dump(value, depth=0):
    pad = "  " * depth
    if isinstance(value, dict):
        items = [pad + "  " + json.dumps(k, ensure_ascii=False) + " : " + dump(v, depth + 1)
                 for k, v in value.items()]
        return "{\n" + (",\n".join(items) if items else "") + "\n" + pad + "}"
    if isinstance(value, list):
        return "[\n" + ",\n".join(pad + "  " + dump(v, depth + 1) for v in value) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def blocks(text):
    decoder = json.JSONDecoder()
    result = []
    for match in re.finditer(r'^    ("(?:[^"\\]|\\.)*")\s*:\s*', text, re.M):
        _, end = decoder.raw_decode(text, match.end())
        result.append((json.loads(match[1]), match.start(), end))
    if [k for k, _, _ in result] != list(json.loads(text)["strings"]):
        raise ValueError("unsupported catalog entry indentation")
    return result


def merge(base, target, source):
    newline = "\r\n" if "\r\n" in target else "\n"
    old, main, branch = [json.loads(t)["strings"] for t in (base, target, source)]
    missing = object()
    conflicts = [k for k in main.keys() | branch.keys() | old.keys()
                 if main.get(k, missing) != branch.get(k, missing)
                 and main.get(k, missing) != old.get(k, missing)
                 and branch.get(k, missing) != old.get(k, missing)]
    if conflicts:
        raise ValueError("value conflicts: " + ", ".join(json.dumps(k) for k in sorted(conflicts)))
    try:
        blocks(target)
    except ValueError:
        target = (dump(json.loads(target)) + "\n").replace("\n", newline)
    for key in old.keys() - branch.keys():
        entries = blocks(target)
        for index, (name, start, end) in enumerate(entries):
            if name != key:
                continue
            if index + 1 < len(entries):
                target = target[:start] + target[entries[index + 1][1]:]
            elif index:
                target = target[:entries[index - 1][2]] + target[end:]
            else:
                target = target[:start] + target[end:]
            break
    for key in branch.keys() & old.keys() & main.keys():
        if branch[key] != old[key] and main[key] == old[key]:
            _, start, end = next(entry for entry in blocks(target) if entry[0] == key)
            block = "    " + json.dumps(key, ensure_ascii=False) + " : " + dump(branch[key], 2)
            target = target[:start] + block.replace("\n", newline) + target[end:]
    for key in sorted(branch):
        if key in old:
            continue
        if key in main:
            continue
        entries = blocks(target)
        block = ("    " + json.dumps(key, ensure_ascii=False) + " : " + dump(branch[key], 2)).replace("\n", newline)
        after = next((start for name, start, _ in entries if name > key), None)
        if after is not None:
            target = target[:after] + block + "," + newline + target[after:]
        elif entries:
            end = entries[-1][2]
            target = target[:end] + "," + newline + block + target[end:]
        else:
            match = re.search(r'"strings"\s*:\s*\{', target)
            target = target[:match.end()] + newline + block + target[match.end():]
    json.loads(target)
    return target


def git(*args):
    return subprocess.check_output(["git", "-C", str(Path.cwd()), *args], text=True).strip("\n")


def git_inputs(main_ref, catalog=CATALOG):
    incoming = next((r for r in ("MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD")
                     if subprocess.run(["git", "-C", str(Path.cwd()), "rev-parse", "--verify", "-q", r],
                                       capture_output=True).returncode == 0), None)
    if incoming is None:
        raise ValueError("no merge, rebase or cherry-pick in progress")
    refs = ["HEAD", incoming]
    matches = [r for r in refs if subprocess.run(
        ["git", "-C", str(Path.cwd()), "merge-base", "--is-ancestor", main_ref, r], capture_output=True).returncode == 0]
    if len(matches) != 1:
        matches = [r for r in refs if git("rev-parse", r) == git("rev-parse", main_ref)]
    if len(matches) != 1:
        raise ValueError("cannot identify upstream side; set --main-ref to its exact commit")
    upstream = matches[0]
    branch = next(r for r in refs if r != upstream)
    try:
        base = git("show", ":1:" + catalog)
    except subprocess.CalledProcessError:
        ancestor = git("merge-base", *refs) if incoming == "MERGE_HEAD" else git("rev-parse", incoming + "^")
        base = git_catalog(ancestor, catalog)
    target = git_catalog(upstream, catalog)
    return base, target, git_catalog(branch, catalog)


def git_catalog(ref, catalog):
    if catalog not in git('ls-tree', '-r', '--name-only', ref).splitlines():
        return dump({'sourceLanguage': 'en', 'strings': {}, 'version': '1.0'}) + '\n'
    return subprocess.check_output(['git', '-C', str(Path.cwd()), 'show', ref + ':' + catalog]).decode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--git", action="store_true")
    parser.add_argument("--main-ref", default="origin/main")
    parser.add_argument("--catalog", default=CATALOG)
    parser.add_argument("files", nargs="*")
    args = parser.parse_args()
    try:
        if args.git:
            inputs = git_inputs(args.main_ref, args.catalog)
            out = Path(git("rev-parse", "--show-toplevel")) / args.catalog
        else:
            if len(args.files) != 4:
                parser.error("expected BASE MAIN BRANCH OUT")
            *paths, output = args.files
            inputs = [Path(p).read_bytes().decode() for p in paths]
            out = Path(output)
        out.write_text(merge(*inputs))
        if args.git:
            git("add", "--", str(out))
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit("xcstrings-union: " + str(error))


if __name__ == "__main__":
    main()
