# Branch cleanup

PR discovery explicitly targets `kaczordodgers/notchcast`. Ancestry and patch-equivalence proof require a tip at least 24 hours old. A closed PR's `Landed on main as` comment bypasses that age guard only when its author is `kaczordodgers`, its squash-of tip equals the current branch tip, and `upstream/main..origin/main` contains a commit subject starting with `Notchcast:` and ending with ` (#<PR number>)`. Sync rebases rewrite the landed SHA, so its ancestry is not proof. Missing `upstream/main` refuses pruning; fetch upstream first. All other keep rules still apply. Dry runs print candidate names. Failed local worktree or branch removals warn, count as kept with reason `remove failed`, and allow the run to continue.

`land.sh` deletes unchanged origin and local heads after closing a PR. Fork heads and moved tips stay; deletion failures only warn.

`prune-branches.py --remote --local --dry-run --log /path/to/ledger.tsv` reports candidates without changing refs or worktrees. Remove `--dry-run` to prune. The required append-only ledger records each name, tip, kind and path before deletion. Comment discovery covers the most recent 1000 closed PRs; older branches require ancestry or patch equivalence proof.

The optional private key `NOTCHCAST_WORKTREE_ROOTS` belongs in `~/.config/notchcast/private.env`, alongside the optional hooks listed in `notchcast/README.md`. Its value is colon-separated absolute parent directories allowed for worktree removal. Without it, checked-out local branches stay. Dirty, locked and outside-root worktrees always stay.

`bash notchcast/install-launchd.sh prune` installs `notchcast.prune` for Sunday at 04:00, running remote and local pruning with `~/Library/Logs/notchcast/pruned-branches.tsv`. Installation does not run pruning immediately. Roots are captured at installation; reinstall this mode after changing them. The `all` mode does not opt into pruning.
