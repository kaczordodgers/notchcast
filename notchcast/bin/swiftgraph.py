#!/usr/bin/env python3
"""Approximate Swift file coupling using lexical type references (stdlib only).

Scans Tinycast/**/*.swift by default; --all-sources includes other roots. Module depth counts
folders below Tinycast; other source roots are prefixed with their root name.
References resolve to every matching primary declaration file: ambiguous names
overestimate coupling; extensions are not targets. No compiler/type resolution.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import subprocess
import time

TOKEN = re.compile(r'`?[A-Za-z_][A-Za-z_0-9]*`?|[{}.]')
REGISTRIES = ('CommandID', 'SettingsTab', 'PaletteMode', 'SettingsFileKey', 'HotKeyAction')


def strip_literals(source):
    """Blank nested comments and ordinary/raw/multiline strings, preserving lines.

    Interpolation is blanked with its enclosing string. Swift regex literals
    are not parsed; references inside them may be false positives.
    """
    result = list(source)
    i, length = 0, len(source)
    while i < length:
        start = i
        if source.startswith('//', i):
            end = source.find('\n', i)
            i = length if end < 0 else end
        elif source.startswith('/*', i):
            i += 2
            depth = 1
            while i < length and depth:
                if source.startswith('/*', i):
                    depth += 1
                    i += 2
                elif source.startswith('*/', i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
        else:
            match = re.match(r'(#+)?("""|")', source[i:]) if source[i] in '#"' else None
            if not match:
                i += 1
                continue
            hashes, quote = match.group(1) or '', match.group(2)
            i += len(match.group())
            closing = quote + hashes
            escape = '\\' + hashes
            while i < length:
                if source.startswith(escape, i):
                    i += len(escape) + 1
                elif source.startswith(closing, i):
                    i += len(closing)
                    break
                else:
                    i += 1
        for pos in range(start, min(i, length)):
            if result[pos] != '\n':
                result[pos] = ' '
    return ''.join(result)


def declarations(clean):
    tokens = list(TOKEN.finditer(clean))
    depth, found, spans = 0, [], set()
    for index, token in enumerate(tokens):
        word = token.group().strip('`')
        if word == '{':
            depth += 1
        elif word == '}':
            depth = max(0, depth - 1)
        elif depth == 0 and word in {'class', 'struct', 'enum', 'protocol', 'actor', 'extension'}:
            if index + 1 >= len(tokens):
                continue
            name_token = tokens[index + 1]
            name = name_token.group().strip('`')
            # 'class func' and 'class var' are modifiers, not declarations.
            if name in {'func', 'var', 'let', 'subscript'} or not re.fullmatch(r'[A-Za-z_]\w*', name):
                continue
            if word != 'extension':
                spans.add(name_token.start())
            if word == 'extension':
                cursor = index + 2
                while cursor + 1 < len(tokens) and tokens[cursor].group() == '.':
                    part = tokens[cursor + 1]
                    name += '.' + part.group().strip('`')
                    # Extension targets remain references to the original type.
                    cursor += 2
            found.append({'kind': word, 'name': name})
    return found, spans


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def churn_counts(repo, since):
    raw = git(repo, 'log', '--since=' + since, '--format=%x00SWIFTGRAPH_COMMIT%x00',
              '--name-only', '-z', '--no-renames', '--', '*.swift')
    counts, touched = Counter(), set()
    for item in raw.decode('utf-8', 'surrogateescape').split('\0'):
        item = item.lstrip('\n')
        if item == 'SWIFTGRAPH_COMMIT':
            counts.update(touched)
            touched.clear()
        elif item:
            touched.add(item)
    counts.update(touched)
    return counts


def build(repo, outdir, depth, all_sources=False):
    started = time.perf_counter()
    now = datetime.now(timezone.utc)
    since = (now - timedelta(days=180)).isoformat()
    churn = churn_counts(repo, since)
    nodes, references, symbols = {}, {}, defaultdict(set)
    excluded = {'.git', '.build', 'build', 'DerivedData', 'node_modules'}
    for path in sorted((repo if all_sources else repo / 'Tinycast').rglob('*.swift')):
        relative = path.relative_to(repo)
        if any(part.startswith('.') or part in excluded for part in relative.parts[:-1]):
            continue
        key = relative.as_posix()
        source = path.read_text(encoding='utf-8')
        clean = strip_literals(source)
        types, spans = declarations(clean)
        folders = relative.parts[:-1]
        module = '/'.join(folders[1:1 + depth] if folders and folders[0] == 'Tinycast' else folders[:depth + 1]) or '(root)'
        nodes[key] = {'module': module, 'types': types, 'loc': len(source.splitlines()),
                      'churn': churn[key], 'fan_in': 0, 'fan_out': 0,
                      'imports': sorted(set(re.findall(r'\bimport\s+(?:(?:class|struct|enum|protocol|func|var|let|typealias)\s+)?([\w.]+)', clean)))}
        references[key] = {token.group().strip('`') for token in TOKEN.finditer(clean)
                           if token.start() not in spans}
        for declaration in types:
            # References resolve to primary declarations only; extensions (incl. of
            # String/View/...) would otherwise link every file to every extender.
            if declaration['kind'] != 'extension':
                symbols[declaration['name'].split('.')[-1]].add(key)
    adjacency = {}
    module_edges = defaultdict(Counter)
    for key, refs in references.items():
        targets = set()
        for name in refs:
            targets.update(symbols.get(name, ()))
        targets.discard(key)
        adjacency[key] = sorted(targets)
        nodes[key]['fan_out'] = len(targets)
        for target in targets:
            nodes[target]['fan_in'] += 1
            origin_module, target_module = nodes[key]['module'], nodes[target]['module']
            if origin_module != target_module:
                module_edges[origin_module][target_module] += 1
    modules = sorted({node['module'] for node in nodes.values()})
    module_adjacency = {module: dict(sorted(module_edges[module].items())) for module in modules}
    counts = {'files': len(nodes), 'types': sum(len(n['types']) for n in nodes.values()),
              'unique_type_names': len(symbols), 'edges': sum(map(len, adjacency.values())),
              'modules': len(modules), 'module_edges': sum(map(len, module_adjacency.values()))}
    metadata = {'head': git(repo, 'rev-parse', 'HEAD').decode().strip(),
                'generated_at': now.isoformat(), 'scope': 'repository' if all_sources else 'Tinycast', 'churn_since': since, 'module_depth': depth,
                'edge_weight': 'distinct directed file pairs; module self-edges omitted',
                'limitations': 'Lexical approximation; ambiguous names resolve to all primary declaration files; extensions are not reference targets. Declaration names except extension targets excluded from references. Nested declarations and typealiases not indexed. Strings including interpolations and comments stripped. Regex literals not parsed. No target/conditional compilation resolution. Churn counts reachable commits, no rename following.',
                'counts': counts}
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / 'graph.json').write_text(json.dumps({'metadata': metadata, 'nodes': nodes,
        'file_adjacency': adjacency, 'module_adjacency': module_adjacency}, indent=2) + '\n')
    dot = ['digraph modules {', '  rankdir=LR;']
    mmd = ['flowchart LR']
    ids = {module: 'm' + str(index) for index, module in enumerate(modules)}
    for module in modules:
        dot.append('  ' + json.dumps(module) + ';')
        mmd.append(f'  {ids[module]}[{json.dumps(module)}]')
    for origin, targets in module_adjacency.items():
        for target, weight in targets.items():
            dot.append(f'  {json.dumps(origin)} -> {json.dumps(target)} [label="{weight}", weight={weight}];')
            mmd.append(f'  {ids[origin]} -->|{weight}| {ids[target]}')
    (outdir / 'modules.dot').write_text('\n'.join(dot + ['}']) + '\n')
    (outdir / 'modules.mmd').write_text('\n'.join(mmd) + '\n')
    lines = ['# Coupling and upstream churn', '', f'HEAD: `{metadata["head"]}`; churn since {since}.', '',
             'Score = incoming file count × commits touching file in the last 180 days.', '',
             '| File | Fan-in | Fan-out | Churn | Score |', '| --- | ---: | ---: | ---: | ---: |']
    ranked = sorted(nodes, key=lambda k: (-nodes[k]['fan_in'] * nodes[k]['churn'], -nodes[k]['fan_in'], k))
    for key in ranked[:30]:
        n = nodes[key]
        lines.append(f'| `{key}` | {n["fan_in"]} | {n["fan_out"]} | {n["churn"]} | {n["fan_in"] * n["churn"]} |')
    lines += ['', '## Registry enums', '', '| Registry | File | Fan-in |', '| --- | --- | ---: |']
    for registry in REGISTRIES:
        matches = [k for k, n in nodes.items() if {'kind': 'enum', 'name': registry} in n['types']]
        for key in matches:
            lines.append(f'| {registry} | `{key}` | {nodes[key]["fan_in"]} |')
        if not matches:
            lines.append(f'| {registry} | Not found | — |')
    lines += ['', metadata['limitations'], '']
    (outdir / 'hotspots.md').write_text('\n'.join(lines))
    print(json.dumps({**counts, 'runtime_seconds': round(time.perf_counter() - started, 3)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path)
    parser.add_argument('outdir', type=Path)
    parser.add_argument('--module-depth', type=int, default=2)
    parser.add_argument('--all-sources', action='store_true', help='Include tests and helper roots outside Tinycast')
    args = parser.parse_args()
    if args.module_depth < 1:
        parser.error('--module-depth must be positive')
    repo, outdir = args.repo.expanduser().resolve(), args.outdir.expanduser().resolve()
    if not repo.is_dir():
        parser.error('repo must be a directory')
    build(repo, outdir, args.module_depth, args.all_sources)


if __name__ == '__main__':
    main()
