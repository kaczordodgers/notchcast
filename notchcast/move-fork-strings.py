#!/usr/bin/env python3
"""Move fork-only catalog entries and route their Swift literals to the Notchcast table."""
import argparse
import json
from pathlib import Path
import re
import runpy
import subprocess
import sys
import textwrap

ROOT = Path(__file__).resolve().parent.parent
CONFIG = runpy.run_path(str(ROOT / 'notchcast/ci.py'))['config']()
LOCAL = 'Tinycast/Resources/Localizable.xcstrings'
FORK = 'Tinycast/Resources/Notchcast.xcstrings'
LOCALES = {'de', 'es', 'fr', 'ja', 'ko', 'pt', 'ru', 'zh-Hans'}
REFERENCED = runpy.run_path(str(ROOT / 'notchcast/check-xcstrings-order.py'))['referenced']
DUMP = runpy.run_path(str(ROOT / 'notchcast/xcstrings-union.py'))['dump']


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def literals(source):
    """Yield complete Swift literals, skipping comments and balancing interpolations."""
    index = 0
    while index < len(source):
        if source.startswith('//', index):
            end = source.find('\n', index)
            index = len(source) if end < 0 else end
        elif source.startswith('/*', index):
            depth = 1
            index += 2
            while depth and index < len(source):
                if source.startswith('/*', index):
                    depth += 1
                    index += 2
                elif source.startswith('*/', index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
        elif source[index] == '"':
            start = index
            quote = '"""' if source.startswith('"""', index) else '"'
            index += len(quote)
            while index < len(source):
                if source.startswith(quote, index):
                    index += len(quote)
                    break
                if source.startswith('\\(', index):
                    depth = 1
                    index += 2
                    while depth and index < len(source):
                        if source[index] == '(':
                            depth += 1
                        elif source[index] == ')':
                            depth -= 1
                        elif source[index] == '"':
                            nested = next(literals(source[index:]), None)
                            if nested:
                                index += nested[1]
                                continue
                        index += 1
                elif source[index] == '\\':
                    index += 2
                else:
                    index += 1
            yield start, index, source[start:index]
        else:
            index += 1


def rewrite(source, keys):
    edits = []
    count = 0
    static = {json.dumps(key.replace('%%', '%'), ensure_ascii=False) for key in keys}
    dynamic = [key for key in keys if '%' in key]
    for start, end, literal in literals(source):
        match_literal = literal
        if literal.startswith('"""'):
            body = re.sub(r'\\\n\s*', '', literal[3:-3])
            match_literal = json.dumps(textwrap.dedent(body).strip('\n'), ensure_ascii=False)
        candidates = keys if literal.startswith('"""') else dynamic
        if literal not in static and not (('\\(' in literal or literal.startswith('"""')) and any(
                REFERENCED(key, match_literal) for key in candidates)):
            continue
        before = source[:start]
        after = source[end:]
        if re.search(r'\btable(?:Name)?:\s*$', before):
            continue
        if re.search(r'Logger\([^\n]*category:\s*$', before):
            continue
        if re.search(r'NSError\(domain:\s*$', before):
            continue
        if re.search(r'DownloadTool\(name:\s*$', before):
            continue
        if re.search(r'\bcaptureFileName\(kind:\s*$', before):
            continue
        if re.search(r'\.(?:appending\(path:|appendingPathComponent\()\s*$', before):
            continue
        if re.search(r'"com\.apple\.[^"]+":\s*$', before):
            continue
        # A command("slug", "Name") helper localizes the name with the fork table itself.
        if re.search(r'\bcommand\(\s*"[^"]+",\s*$', before):
            continue
        # Plain dictionary values (gallery sample text) are not localized, so there is nothing to route.
        if re.search(r'"[\w-]+":\s*$', before):
            continue
        if re.search(r'keywords:\s*\[[^\n\]]*$', before):
            continue
        if re.search(r'\bcase\s*$', before):
            continue
        if re.search(r'(?:restart:[^\n]*|subtitle\()\s*$', before) and literal == '"Finder"':
            continue
        if re.search(r'arguments:\s*\[[^\n\]]*$', before):
            continue
        if re.search(r'ExecutableLocator\.find\(\s*$', before):
            continue
        if re.search(r'\bproperties\[\s*$', before):
            continue
        if re.match(r'\s*,\s*table(?:Name)?:\s*"Notchcast"', after):
            continue
        if re.search(r'(?:String\(\s*localized:|LocalizedStringResource\()\s*$', before):
            edits.append((end, end, ', table: "Notchcast"'))
        elif re.search(r'\bText\(\s*$', before):
            edits.append((end, end, ', tableName: "Notchcast"'))
        elif re.search(r'\b(?:TextField|SecureField|Section|Button|Toggle|Picker|LabeledContent)\(\s*$', before):
            edits.append((start, end, 'String(localized: ' + literal + ', table: "Notchcast")'))
        elif re.search(r'\bButton\([^\n]*[?:]\s*$', before):
            edits.append((start, end, 'String(localized: ' + literal + ', table: "Notchcast")'))
        elif re.search(r'\.(?:help|accessibility(?:Label|Hint|Value))\(\s*$', before):
            edits.append((start, end, 'String(localized: ' + literal + ', table: "Notchcast")'))
        elif (re.search(r'(?:SettingsRowTitle|\.init)\([^\n"]*,\s*$', before)
              or re.search(r'(?:title|subtitle|prompt):\s*$', before)
              or re.search(r'var \w+: LocalizedStringResource\s*\{[^\n]*[?:]\s*$', before)
              or (re.search(r'case [^\n]+:\s*$', before)
                  and re.search(r'var \w+: LocalizedStringResource\s*\{[^}]*$', before))
              or re.search(r'LocalizedStringResource\s*=\s*$', before)):
            edits.append((start, end, 'LocalizedStringResource(' + literal + ', table: "Notchcast")'))
        else:
            # Nonlocalized infrastructure may share a spelling with a visible title.
            if literal == '"Notchcast"':
                continue
            raise ValueError('unrecognized fork literal context: ' + before.splitlines()[-1] + literal)
        count += 1
    for start, end, replacement in reversed(edits):
        source = source[:start] + replacement + source[end:]
    return source, count


def plan(upstream):
    original = (ROOT / LOCAL).read_bytes()
    current = json.loads(original)
    upstream_catalog = json.loads(upstream)
    fork_path = ROOT / FORK
    fork = json.loads(fork_path.read_bytes()) if fork_path.exists() else {
        'sourceLanguage': 'en', 'strings': {}, 'version': '1.0'}
    for key, value in current['strings'].items():
        if key in upstream_catalog['strings']:
            if value != upstream_catalog['strings'][key]:
                raise ValueError('shared upstream key changed: ' + key)
            continue
        if key in fork['strings'] and fork['strings'][key] != value:
            raise ValueError('conflicting fork translation: ' + key)
        fork['strings'][key] = value
    for key, value in fork['strings'].items():
        if value.get('shouldTranslate') is False:
            continue
        missing = LOCALES - value.get('localizations', {}).keys()
        if missing:
            raise ValueError(f'{key}: missing locales {sorted(missing)}')
    changes = {}
    if original != upstream:
        changes[ROOT / LOCAL] = upstream
    if fork['strings']:
        fork['strings'] = dict(sorted(fork['strings'].items()))
        content = (DUMP(fork) + '\n').encode()
        if not fork_path.exists() or fork_path.read_bytes() != content:
            changes[fork_path] = content
    counts = {}
    for path in sorted((ROOT / 'Tinycast').rglob('*.swift')):
        source = path.read_text()
        updated, count = rewrite(source, fork['strings'])
        if updated != source:
            changes[path] = updated.encode()
            counts[str(path.relative_to(ROOT))] = count
    return changes, len(fork['strings']), counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--fetch', action='store_true', help='refresh upstream/main by URL')
    args = parser.parse_args()
    if args.fetch:
        if args.check:
            parser.error('--check cannot be combined with --fetch')
        git('fetch', "https://github.com/{}.git".format(CONFIG['UPSTREAM_REPO']),
            'main:refs/remotes/upstream/main')
    try:
        changes, keys, counts = plan(git('show', 'upstream/main:' + LOCAL))
        if not args.check:
            for path, content in changes.items():
                path.write_bytes(content)
        print(f'fork strings: {keys} keys, {sum(counts.values())} call sites, '
              f'{len(changes)} files pending' if args.check else
              f'fork strings: {keys} keys, {sum(counts.values())} call sites, {len(changes)} files changed')
        for path, count in counts.items():
            print(f'  {count}: {path}')
        return bool(changes) if args.check else 0
    except (ValueError, subprocess.CalledProcessError) as error:
        print('fork strings: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
