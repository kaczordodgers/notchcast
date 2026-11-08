#!/usr/bin/env python3
"""Local fork-only drift gates and post-landing threshold reports."""
import argparse
from collections import Counter, defaultdict
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
TOOLS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('swiftgraph', TOOLS / 'bin/swiftgraph.py')
swiftgraph = importlib.util.module_from_spec(spec)
spec.loader.exec_module(swiftgraph)
KERNEL = {'Features/Notchcast'}
RULES = {'1': ('boundaries', 'core-lookups', 'upstream-folders'),
         '2': ('file-size',), '3': ('dead', 'test-only'), '4': ('clones', 'constants')}
WAIVER = re.compile(r'// drift: keep \S.*$')
IDENT = re.compile(r'[A-Za-z_]\w*')
DECL = re.compile(r'^[ \t]*((?:@\w+(?:\([^\n]*?\))?\s+)*)'
                  r'((?:(?:public|private|fileprivate|internal|final|nonisolated|static|class|'
                  r'mutating|override|indirect|convenience|required|lazy|weak)\s+)*)'
                  r'(class|struct|enum|protocol|actor|typealias|func|let|var)\s+`?([A-Za-z_]\w*)', re.M)
SKIP_ATTR = ('@objc', '@main', '@IBAction', '@NSApplicationMain', '@Environment', '@State',
             '@Binding', '@Bindable', '@AppStorage', '@propertyWrapper')
PATTERNS = {'try?': r'\btry\?', 'Task.sleep': r'\bTask\.sleep\b', 'Process()': r'\bProcess\s*\(\s*\)',
            'tool-paths': r'"/(?:usr/|bin/|sbin/|opt/)[^"\n]+"',
            'cancellation-loops': r'\bwhile\s+!Task\.isCancelled\b'}


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def config(root):
    return dict(re.findall(r'^(\w+)=([^\n]+)$', (root / 'notchcast/config.env').read_text(), re.M))


def upstream_base(root):
    exists = subprocess.run(['git', '-C', str(root), 'rev-parse', '-q', '--verify',
                             'refs/remotes/upstream/main'], capture_output=True)
    if exists.returncode:
        repo = config(root)['UPSTREAM_REPO']
        subprocess.run(['git', '-C', str(root), 'fetch', '-q', '--no-tags',
                        f'https://github.com/{repo}.git',
                        '+refs/heads/main:refs/remotes/upstream/main'], check=True)
    return git(root, 'merge-base', 'HEAD', 'refs/remotes/upstream/main')


def folder(path):
    parts = Path(path).parts
    return '/'.join(parts[1:3]) if len(parts) > 3 and parts[1] == 'Features' else parts[1]


def unwaived(source):
    return '\n'.join('' if WAIVER.search(line) else line for line in source.split('\n'))


def sources(root, prefix):
    return {p.relative_to(root).as_posix(): p.read_text() for p in sorted((root / prefix).rglob('*.swift'))
            if not p.name.endswith('.generated.swift')}


def clone_counts(root, files):
    version = config(root)['JSCPD_VERSION']
    if not re.fullmatch(r'4\.\d+\.\d+', version):
        raise ValueError('JSCPD_VERSION must pin jscpd 4 to an exact version')
    if not shutil.which('npx'):
        raise ValueError('gate 4 requires npx (Node 20+); duplicates were not checked')
    with tempfile.TemporaryDirectory(prefix='drift-clones.') as work:
        work = Path(work)
        tree, output = work / 'sources', work / 'report'
        tree.mkdir()
        for path, text in files.items():
            target = tree / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(unwaived(text))
        result = subprocess.run(['npx', '-y', f'jscpd@{version}', '--min-tokens', '70', '--min-lines', '6',
                                 '--format', 'swift', '--reporters', 'json', '--silent',
                                 '--output', str(output), str(tree)], capture_output=True, text=True)
        if result.returncode:
            raise ValueError(f'gate 4 jscpd failed ({result.returncode}): {result.stderr.strip()}')
        report = json.loads((output / 'jscpd-report.json').read_text())
        counts = Counter()
        for clone in report['duplicates']:
            pair = []
            for side in ('firstFile', 'secondFile'):
                path = Path(clone[side]['name'])
                if not path.is_absolute():
                    path = Path.cwd() / path
                pair.append(path.resolve().relative_to(tree.resolve()).as_posix())
            if pair[0] != pair[1]:
                counts[' | '.join(sorted(pair))] += 1
        return dict(counts)


def measure(root, upstream, gates):
    prod, tests = sources(root, 'Tinycast'), sources(root, 'Tests')
    added = set(git(root, 'diff', '--diff-filter=A', '--name-only', upstream, '--', '*.swift').splitlines())
    added.update(git(root, 'ls-files', '--others', '--exclude-standard', '--', '*.swift').splitlines())
    ours = {p: text for p, text in prod.items() if p in added}
    our_tests = {p: text for p, text in tests.items() if p in added}
    clean = {p: swiftgraph.strip_literals(unwaived(text)) for p, text in prod.items()}
    observed = {rule: {} for gate in gates for rule in RULES[gate]}
    if '1' in gates:
        with tempfile.TemporaryDirectory(prefix='drift-graph.') as work:
            with contextlib.redirect_stdout(io.StringIO()):
                swiftgraph.build(root, Path(work), 2)
            graph = json.loads((Path(work) / 'graph.json').read_text())
        upstream_folders = {folder(p) for p in prod.keys() - ours.keys()}
        fork_folders = {folder(p) for p in ours} - upstream_folders
        pairs = defaultdict(set)
        for path in ours:
            origin = folder(path)
            if origin not in KERNEL:
                count = len(re.findall(r'\bNotchcastCore\.\w', clean[path]))
                if count:
                    observed['core-lookups'][path] = count
                if origin in upstream_folders:
                    observed['upstream-folders'][path] = 1
            if origin not in fork_folders or origin in KERNEL:
                continue
            names = set(IDENT.findall(clean[path]))
            for target in graph['file_adjacency'].get(path, []):
                dest = folder(target)
                declared = {d['name'] for d in graph['nodes'][target]['types'] if d['kind'] != 'extension'}
                if dest != origin and dest in fork_folders - KERNEL and names & declared:
                    pairs[f'{origin} -> {dest}'].add(path)
        observed['boundaries'] = {pair: len(paths) for pair, paths in pairs.items()}
    if '2' in gates:
        for path, text in (ours | our_tests).items():
            length = len(text.splitlines())
            limit = 600 if path.startswith('Tests/') else 400
            if length > limit and not WAIVER.search(text.splitlines()[-1]):
                observed['file-size'][path] = length
    if '3' in gates:
        tokens = Counter(word for text in clean.values() for word in IDENT.findall(text))
        test_tokens = Counter(word for text in tests.values() for word in IDENT.findall(text))
        declarations = Counter(m[4] for text in clean.values() for m in DECL.finditer(text))
        for path in ours:
            for match in DECL.finditer(clean[path]):
                attrs, mods, kind, name = match.groups()
                if 'override' in mods or any(a in attrs for a in SKIP_ATTR):
                    continue
                if kind in ('let', 'var') and 'static' not in mods and match.group().startswith((' ', '\t')):
                    continue
                if name in ('body', 'init', 'id', 'description', 'hash', 'main', 'makeBody', 'shared'):
                    continue
                if tokens[name] > declarations[name]:
                    continue
                rule = 'test-only' if test_tokens[name] else 'dead'
                observed[rule][f'{path}:{name}'] = 1
    if '4' in gates:
        observed['clones'] = clone_counts(root, ours)
        literals = defaultdict(set)
        for path, text in ours.items():
            text = unwaived(text)
            matches = list(re.finditer(r'(?<![\\#])"([a-z0-9][a-z0-9._/:-]{5,})"', text))
            marked = list(text)
            for match in matches:
                marked[match.start():match.end()] = 'D' + ' ' * (match.end() - match.start() - 1)
            visible = swiftgraph.strip_literals(''.join(marked))
            for match in matches:
                value = match[1]
                if not re.search(r'[._/:-]', value):
                    continue
                if re.search(r'\b(?:systemName|systemImage)\s*:\s*$', text[:match.start()]):
                    continue
                if visible[match.start()] != 'D':
                    continue
                literals[value].add(folder(path))
        observed['constants'] = {key: len(owners) for key, owners in literals.items() if len(owners) > 1}
    return observed, ours, our_tests


def check_counts(observed, baseline):
    problems = []
    for rule, counts in observed.items():
        allowed = baseline[rule]
        for key in sorted(counts.keys() | allowed.keys()):
            actual, limit = counts.get(key, 0), allowed.get(key, 0)
            if actual > limit:
                problems.append(f'{rule}: {key}: {actual} > {limit}')
            elif actual < limit:
                problems.append(f'{rule}: {key}: {actual} < {limit}; lower it in drift-baseline.json')
    return problems


def read_baseline(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'duplicate baseline key: {key}')
            result[key] = value
        return result
    baseline = json.loads(path.read_text(), object_pairs_hook=unique)
    expected = {rule for rules in RULES.values() for rule in rules} | {'alerts'}
    if baseline.keys() != expected:
        raise ValueError('baseline must contain exactly the gate rules and alerts')
    for rule, counts in baseline.items():
        if not isinstance(counts, dict) or any(type(v) is not int or v < 0 for v in counts.values()):
            raise ValueError(f'invalid baseline counts for {rule}')
    return baseline


def compare_baseline(root, base, baseline):
    exists = subprocess.run(['git', '-C', str(root), 'cat-file', '-e',
                             f'{base}:notchcast/drift-baseline.json'], capture_output=True)
    if exists.returncode:
        git(root, 'rev-parse', '--verify', f'{base}^{{commit}}')
        return []
    with tempfile.TemporaryDirectory(prefix='drift-base.') as work:
        path = Path(work) / 'baseline.json'
        path.write_text(git(root, 'show', f'{base}:notchcast/drift-baseline.json'))
        previous = read_baseline(path)
    return [f'{rule}: {key}: {value} > {previous[rule].get(key, 0)}'
            for rule, counts in baseline.items() for key, value in counts.items()
            if key not in previous[rule] or value > previous[rule][key]]


def report_counters(root, upstream, ours, our_tests, periphery):
    counters = {('file-lines', path): len(text.splitlines()) for path, text in ours.items()}
    counters.update({('test-lines', path): len(text.splitlines()) for path, text in our_tests.items()})
    counters['waivers', 'all'] = sum(bool(WAIVER.search(line)) for text in ours.values() for line in text.splitlines())
    for name, pattern in PATTERNS.items():
        counters[name, 'all'] = sum(len(re.findall(pattern, text)) for text in ours.values())
    diff = git(root, 'diff', '--diff-filter=M', '--numstat', upstream, '--', '*.swift')
    counters['upstream-patch-lines', 'all'] = sum(int(line.split('\t')[0]) for line in diff.splitlines()
                                               if not line.split('\t')[2].endswith('.generated.swift')
                                               and line.split('\t')[0].isdigit())
    log = git(root, 'log', '--first-parent', f'{upstream}..HEAD', '--format=%x1e%s%x1f%b')
    counters['fix-no-test', 'all'] = sum(bool(re.match(r'Notchcast: Fix ', entry.lstrip()) and
                                                   re.search(r'^No test: \S', entry, re.M))
                                          for entry in log.split('\x1e'))
    if periphery:
        findings = json.loads(periphery.read_text())
        if not isinstance(findings, list):
            raise ValueError('periphery JSON report must be a list')
        counters['periphery', 'all'] = len(findings)
    return counters


def notify(counters, thresholds, cache, hook, title_prefix='Notchcast: Reduce'):
    available = subprocess.run(['bash', '-c',
                                'if [ -f "$1" ]; then source "$1"; fi; declare -F notchcast_task >/dev/null',
                                'drift-hook', str(hook)], capture_output=True, text=True)
    if available.returncode:
        print('no task hook')
        return
    cache.parent.mkdir(parents=True, exist_ok=True)
    import fcntl
    with (cache.parent / (cache.name + '.lock')).open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous = json.loads(cache.read_text()) if cache.exists() else {}
        current = {}
        for (counter, key), value in sorted(counters.items()):
            threshold = thresholds[counter]
            identity = f'{counter}|{key}'
            if value <= threshold:
                continue
            if identity in previous:
                current[identity] = previous[identity]
                continue
            result = subprocess.run(['bash', '-c',
                                     'if [ -f "$1" ]; then source "$1"; fi\n'
                                     'if declare -F notchcast_task >/dev/null; then\n'
                                     '  notchcast_task "$2" "$3"\n'
                                     'else printf "%s\\n" "no task hook"; exit 3; fi',
                                     'drift-hook', str(hook), f'{title_prefix} {counter}',
                                     f'{counter}, {value}, threshold {threshold}, {key}'],
                                    capture_output=True, text=True)
            if result.stdout:
                print(result.stdout.strip())
            if result.returncode == 0:
                current[identity] = value
            elif result.returncode != 3:
                print(f'task hook failed: {result.stderr.strip()}', file=sys.stderr)
        temporary = cache.with_suffix('.tmp')
        temporary.write_text(json.dumps(current, indent=2, sort_keys=True) + '\n')
        temporary.replace(cache)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=TOOLS.parent)
    parser.add_argument('--upstream', help='Explicit upstream base, for isolated fixtures')
    parser.add_argument('--gates', default='1,2,3,4', choices=('1,2,3', '1,2,3,4', '1', '2', '3', '4'))
    parser.add_argument('--write-baseline', action='store_true', help='Seed or tighten the baseline; never raise existing budgets')
    parser.add_argument('--compare-base', help='Reject budget growth against this commit, without running tools')
    parser.add_argument('--report', action='store_true', help='Print counters and call optional threshold tasks')
    parser.add_argument('--periphery-report', type=Path, help='Optional JSON from a separate indexed Periphery sweep')
    parser.add_argument('--alert-cache', type=Path, default=Path.home() / 'Library/Caches/notchcast/drift-alerts.json')
    parser.add_argument('--task-prefix', default='Notchcast: Reduce', help='Task title prefix for an authorized hook probe')
    args = parser.parse_args()
    root = args.root.resolve()
    path = root / 'notchcast/drift-baseline.json'
    if args.compare_base:
        problems = compare_baseline(root, args.compare_base, read_baseline(path))
        print('\n'.join(problems) if problems else 'PASS: drift baseline did not grow')
        return bool(problems)
    if args.write_baseline and args.gates != '1,2,3,4':
        raise ValueError('writing the baseline requires all gates')
    upstream = args.upstream or upstream_base(root)
    observed, ours, our_tests = measure(root, upstream, args.gates.split(','))
    if args.write_baseline:
        counters = report_counters(root, upstream, ours, our_tests, None)
        observed['alerts'] = {name: value for (name, key), value in counters.items() if key == 'all'}
        observed['alerts'].update({'file-lines': 349, 'test-lines': 549, 'periphery': 0})
        if path.exists():
            previous = read_baseline(path)
            observed['alerts'] = previous['alerts']
            if any(value > previous[rule].get(key, 0) for rule, counts in observed.items()
                   for key, value in counts.items()):
                raise ValueError('cannot raise or add baseline entries')
        path.write_text(json.dumps(observed, indent=2, sort_keys=True) + '\n')
        print('Seeded drift-baseline.json')
        return 0
    baseline = read_baseline(path)
    if args.report:
        print('Counter | Current | Baseline / threshold')
        for rule, counts in observed.items():
            print(f'{rule} | {sum(counts.values())} ({len(counts)} keys) | {sum(baseline[rule].values())}')
        largest = sorted(ours, key=lambda p: (-len(ours[p].splitlines()), p))[:10]
        for file in largest:
            print(f'largest | {file} | {len(ours[file].splitlines())} lines')
        counters = report_counters(root, upstream, ours, our_tests, args.periphery_report)
        for (counter, key), value in sorted(counters.items()):
            if counter not in ('file-lines', 'test-lines') or value > baseline['alerts'][counter]:
                print(f'{counter} | {value} | {baseline["alerts"][counter]} | {key}')
        for rule in ('dead', 'test-only'):
            for key in observed.get(rule, {}):
                print(f'{rule} | {key}')
        notify(counters, baseline['alerts'], args.alert_cache,
               Path.home() / '.config/notchcast/private.env', args.task_prefix)
        return 0
    problems = check_counts(observed, baseline)
    for gate in args.gates.split(','):
        count = sum(len(observed[r]) for r in RULES[gate])
        failed = any(p.split(':', 1)[0] in RULES[gate] for p in problems)
        print(f'gate {gate}: {"FAIL" if failed else "PASS"} ({count} keys)')
    for problem in problems:
        print(problem)
    return bool(problems)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f'drift: FAIL: {error}', file=sys.stderr)
        sys.exit(1)
