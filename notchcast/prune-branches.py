#!/usr/bin/env python3
"""Prune proven landed branches, retaining an append-only recovery ledger."""
import argparse
from collections import Counter
import fnmatch
import json
from pathlib import Path
import re
import subprocess
import time


def run(*args, check=True):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)


def git(*args):
    return run('git', *args).stdout.strip()


def refs(remote):
    prefix = 'refs/remotes/origin/' if remote else 'refs/heads/'
    return {ref[len(prefix):]: sha for ref, sha in
            (line.split() for line in git('for-each-ref', '--format=%(refname) %(objectname)', prefix).splitlines())
            if not ref.endswith('/HEAD')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--remote', action='store_true')
    parser.add_argument('--local', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--log', required=True, type=Path)
    parser.add_argument('--worktree-root', action='append', default=[], type=Path)
    args = parser.parse_args()
    if not (args.remote or args.local):
        parser.error('select --remote and/or --local')
    # A dry run must not even refresh remote-tracking refs in the caller's repository.
    if not args.dry_run:
        git('fetch', '--prune', 'origin')
    git('rev-parse', '--verify', 'origin/main')
    if run('git', 'rev-parse', '--verify', 'upstream/main', check=False).returncode:
        parser.error('upstream/main is missing; fetch upstream before pruning')
    landed_numbers = {int(match[1]) for subject in
                      git('log', '--format=%s', 'upstream/main..origin/main').splitlines()
                      if (match := re.fullmatch(r'Notchcast:.* \(#(\d+)\)', subject))}
    def open_heads():
        opened = run('gh', 'pr', 'list', '-R', 'kaczordodgers/notchcast', '--state', 'open', '-L', '1000', '--json', 'headRefName')
        return {pr['headRefName'] for pr in json.loads(opened.stdout)}

    open_names = open_heads()
    closed = json.loads(run('gh', 'pr', 'list', '-R', 'kaczordodgers/notchcast', '--state', 'closed', '-L', '1000', '--json',
                            'number,headRefName,comments').stdout)
    landed_tips = set()
    for pr in closed:
        if pr['number'] not in landed_numbers:
            continue
        for comment in pr.get('comments', []):
            if (comment.get('author') or {}).get('login') != 'kaczordodgers':
                continue
            for match in re.finditer(r'Landed on main as ([0-9a-f]{40})\b[^\n]*?squash of ([0-9a-f]{40})\b', comment['body']):
                landed_tips.add((pr['headRefName'], match[2]))
    worktrees = {}
    for block in git('worktree', 'list', '--porcelain').split('\n\n'):
        fields = dict(line.partition(' ')[::2] for line in block.splitlines())
        if 'branch' in fields:
            worktrees.setdefault(fields['branch'].removeprefix('refs/heads/'), []).append(fields)
    roots = [root.expanduser().resolve() for root in args.worktree_root]
    home = Path.home().resolve()
    for root in roots:
        if home.is_relative_to(root):
            parser.error(f'--worktree-root {root} contains the home folder; name the agent worktree folder itself')
    kept = Counter()
    candidates = {'remote': [], 'local': []}
    before = {kind: len(refs(kind == 'remote')) for kind in candidates}
    cutoff = time.time() - 86400
    proof = {}
    for kind in candidates:
        if not getattr(args, kind):
            continue
        for name, sha in refs(kind == 'remote').items():
            reason = None
            if name == 'main':
                reason = 'main'
            elif name in open_names:
                reason = 'open PR'
            elif any(fnmatch.fnmatchcase(name, pattern) for pattern in ('nc-design-race-*', 'nc-design-v4-*')):
                reason = 'design'
            elif (name, sha) not in landed_tips and int(git('show', '-s', '--format=%ct', sha)) >= cutoff:
                reason = 'recent'
            trees = worktrees.get(name, []) if kind == 'local' else []
            for tree in trees:
                path = Path(tree['worktree']).resolve()
                if 'locked' in tree:
                    reason = reason or 'locked worktree'
                elif not any(path != root and path.is_relative_to(root) for root in roots):
                    reason = reason or 'worktree outside roots'
                elif run('git', '-C', str(path), 'status', '--porcelain').stdout:
                    reason = reason or 'dirty worktree'
            if reason is None and (name, sha) not in landed_tips:
                if sha not in proof:
                    ancestor = run('git', 'merge-base', '--is-ancestor', sha, 'origin/main', check=False)
                    if ancestor.returncode not in (0, 1):
                        raise RuntimeError(ancestor.stderr)
                    # git cherry skips merge commits, so a hand-resolved merge would otherwise look landed.
                    proof[sha] = ancestor.returncode == 0 or (
                        not git('rev-list', '--merges', 'origin/main..' + sha)
                        and not any(line.startswith('+') for line in git('cherry', 'origin/main', sha).splitlines()))
                if not proof[sha] and (name, sha) not in landed_tips:
                    reason = 'not landed'
            if reason:
                kept[reason] += 1
            else:
                candidates[kind].append((name, sha, trees))
    print(f'Before: remote={before["remote"]} local={before["local"]} worktrees={sum(map(len, worktrees.values()))}')
    for reason, count in sorted(kept.items()):
        print(f'Kept {reason}: {count}')
    print('Candidates: ' + ' '.join(f'{kind}={len(items)}' for kind, items in candidates.items()))
    if args.dry_run:
        for kind, items in candidates.items():
            for name, _, _ in items:
                print(f'Candidate {kind}: {name}')

    def record(name, sha, kind, path=''):
        with args.log.expanduser().open('a') as log:
            log.write(f'{name}\t{sha}\t{kind}\t{path}\n')
            log.flush()

    if not args.dry_run:
        args.log.expanduser().parent.mkdir(parents=True, exist_ok=True)
        for offset in range(0, len(candidates['remote']), 50):
            batch = candidates['remote'][offset:offset + 50]
            # Re-check right before each batch: a PR opened or a branch moved since selection keeps it.
            live = {ref.removeprefix('refs/heads/'): sha for sha, ref in
                    (line.split() for line in git('ls-remote', '--heads', 'origin').splitlines())}
            still_open = open_heads()
            batch = [item for item in batch if live.get(item[0]) == item[1] and item[0] not in still_open]
            if not batch:
                continue
            for name, sha, _ in batch:
                record(name, sha, 'remote')
            pushed = run('git', 'push', '--atomic', 'origin', '--delete', *(name for name, _, _ in batch), check=False)
            if pushed.returncode:
                print(f'Warning: remote delete batch failed, nothing in it deleted: {pushed.stderr.strip()}')
                kept['remove failed'] += len(batch)
        for name, sha, trees in candidates['local']:
            # A commit made since selection keeps both the branch and its worktree.
            if git('rev-parse', 'refs/heads/' + name) != sha:
                print(f'Kept moved local branch: {name}')
                continue
            for tree in trees:
                record(name, sha, 'worktree', tree['worktree'])
                removed = run('git', 'worktree', 'remove', tree['worktree'], check=False)
                if removed.returncode:
                    print(f'Warning: worktree remove failed for {name}: {removed.stderr.strip()}')
                    kept['remove failed'] += 1
                    break
            else:
                record(name, sha, 'local')
                removed = run('git', 'branch', '-D', '--', name, check=False)
                if removed.returncode:
                    print(f'Warning: branch remove failed for {name}: {removed.stderr.strip()}')
                    kept['remove failed'] += 1
        if args.local:
            git('worktree', 'prune')
        git('fetch', '--prune', 'origin')
    print(f'After: remote={len(refs(True))} local={len(refs(False))}; dry-run={args.dry_run}')
    if kept['remove failed']:
        print(f'Kept remove failed: {kept["remove failed"]}')


if __name__ == '__main__':
    main()
