# Leak points: the maintainer's employer must never appear

Notchcast is public. Nothing in it may name or point at the maintainer's employer: not its name, domain, email addresses, bundle id prefixes, internal repositories or paths. Where a leak can come from, and what stops it:

- **Commit identities.** A Mac's global git identity can be a work address, and every commit made the default way carries it. Each clone sets a repo-local identity before the first commit (`user.name`, a GitHub noreply `user.email`); workflow commits use `github-actions[bot]`.
- **Commit messages and labels.** Messages, LaunchAgent labels, bundle ids and signing identities are as public as code. Labels are `notchcast.<name>`, the bundle id is `app.notchcast`.
- **Unpushed and dangling objects.** A local commit with a bad message stays in the clone's object store and reflog, and tools that keep their own refs can keep it reachable. Never push a branch that contains one; rebuild the branch from `origin` instead.
- **Copied files.** Scripts, templates, design tokens or notes copied from private repositories bring absolute paths, internal names and ids with them. Review every copied file for paths and names before committing it.
- **Pushing to upstream.** Each clone sets `git remote set-url --push upstream DISABLED`.

Enforcement: `notchcast/check-identity.sh` runs in the pre-commit and commit-msg hooks (`git config core.hooksPath notchcast/githooks`) and in `.github/workflows/leaks.yml`. It fails on the employer name in tracked files, commit messages, and author or committer identities; gitleaks covers secrets in the same places.
