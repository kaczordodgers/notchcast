#!/usr/bin/env python3
"""Keep checked documentation, fixtures and upstream literals aligned with config.env."""
import argparse
import json
from pathlib import Path
import runpy
import subprocess

ROOT = Path(__file__).resolve().parent.parent
KEYS = ('UPSTREAM_REPO', 'FORK_REPO', 'MAINTAINER_NAME', 'MAINTAINER_EMAIL', 'TESTED_CONTEXT')


def inventory(root, cfg):
    paths = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', 'notchcast', '.github', 'Scripts'],
        cwd=root).decode().split('\0')
    found = {}
    for path in sorted(set(paths) - {'', 'notchcast/config.env'}):
        try:
            text = (root / path).read_text()
        except UnicodeDecodeError:
            continue
        counts = {key: text.count(cfg[key]) for key in KEYS if cfg[key] in text}
        if counts:
            found[path] = counts
    return found


def check(root, cfg):
    expected = json.loads((root / 'notchcast/config-literals.json').read_text())
    found = inventory(root, cfg)
    return [f'{path}: expected {expected.get(path, {})}, found {found.get(path, {})}'
            for path in sorted(found.keys() | expected.keys()) if found.get(path, {}) != expected.get(path, {})]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list', action='store_true', help='print the checked literal inventory')
    args = parser.parse_args()
    cfg = runpy.run_path(str(ROOT / 'notchcast/ci.py'))['config']()
    if args.list:
        print(json.dumps(inventory(ROOT, cfg), indent=2))
        return 0
    errors = check(ROOT, cfg)
    print('\n'.join(errors) if errors else 'config literals: PASS')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
