#!/usr/bin/env python3
"""Reject fork strings in the upstream table and broken explicit table references."""
import json
from pathlib import Path
import re
import runpy
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def check():
    tools = runpy.run_path(str(ROOT / 'notchcast/move-fork-strings.py'))
    local = json.loads((ROOT / tools['LOCAL']).read_bytes())['strings']
    fork_path = ROOT / tools['FORK']
    if not fork_path.exists():
        return ['Notchcast.xcstrings is missing; run move-fork-strings.py']
    fork = json.loads(fork_path.read_bytes())['strings']
    # CI and local-ci check catalogs before their own upstream fetch step.
    if subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '-q', '--verify', 'refs/remotes/upstream/main'],
                      capture_output=True).returncode:
        subprocess.check_call(['git', '-C', str(ROOT), 'fetch', '-q', '--no-tags',
                               'https://github.com/abue-ammar/tinycast.git', '+refs/heads/main:refs/remotes/upstream/main'])
    upstream = json.loads(subprocess.check_output([
        'git', '-C', str(ROOT), 'show', 'upstream/main:' + tools['LOCAL']]))['strings']
    errors = ['fork key in Localizable: ' + key for key in local.keys() - upstream.keys()]
    errors += ['key in both catalogs: ' + key for key in local.keys() & fork.keys()]
    for key, entry in fork.items():
        if entry.get('shouldTranslate') is not False:
            missing = tools['LOCALES'] - entry.get('localizations', {}).keys()
            if missing:
                errors.append(f'{key}: missing locales {sorted(missing)}')
    for path in (ROOT / 'Tinycast').rglob('*.swift'):
        source = path.read_text()
        for _, end, literal in tools['literals'](source):
            if re.match(r'\s*,\s*table(?:Name)?:\s*"Notchcast"', source[end:]):
                if not any(tools['REFERENCED'](key, literal) for key in fork):
                    errors.append(f'{path.relative_to(ROOT)}: missing key for {literal}')
        _, pending = tools['rewrite'](source, fork)
        if pending:
            errors.append(f'{path.relative_to(ROOT)}: {pending} fork literals use the default table')
    return errors


if __name__ == '__main__':
    problems = check()
    if not problems:
        subprocess.run(['node', str(ROOT / 'notchcast/check-localizations.js')], check=True)
    print('\n'.join(problems) if problems else 'fork strings: PASS')
    sys.exit(bool(problems))
