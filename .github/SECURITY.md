# Security policy

## Reporting a vulnerability

Report security problems privately through [GitHub's private vulnerability reporting](https://github.com/kaczordodgers/notchcast/security/advisories/new). Do not open a public issue.

Include the Notchcast version (About Notchcast in the menu bar, or the release tag), your macOS version, the steps to reproduce and what an attacker could do with it.

## Scope

- Notchcast's own code: everything our commits add on top of upstream Tinycast, including the privileged helper (`notchcast/root/`), the local agent bridge and command line tool, deeplinks (`notchcast://`), the update installer (`notchcast/update.sh`, `notchcast/install-app.sh`) and the release signing in `.github/workflows/`.
- Upstream Tinycast code that Notchcast ships unchanged: report it to [Tinycast](https://github.com/abue-ammar/tinycast) as well, since the fix belongs there and reaches Notchcast with the next sync.

## Supported versions

Only the newest release and the newest `snapshot` pre-release get fixes. Fixes ship in the next snapshot built from `main`.
