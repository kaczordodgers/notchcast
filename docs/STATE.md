# Notchcast state

The one state file of the fork: Damian's decisions first, then Current, Next, Log. This file is ours, not upstream's; how the fork works is in [notchcast/README.md](../notchcast/README.md) and our docs live in [notchcast/docs/](../notchcast/docs/). Open work and the landing queue live in the maintainers' tracker and in git, never copied here.

## Damian's decisions (binding, check before asking him)

- Our commits must replay cleanly onto every upstream commit: touch as few upstream files and lines as possible.
- Upstream's root `AGENTS.md` and `docs/` stay exactly as upstream ships them; our rules go in `notchcast/` and this file.
- Our own code, no Raycast extensions, built as if upstream shipped it, in upstream's look.
- Never import Tinycast's clipboard history (decided more than once; do not propose it again).
- Our own extensions show no category subtitles.
- Settings: one Notchcast sidebar category with one tab per module; every switch works, its commands with it; preferences in a fork-local `UserDefaults` store; no hidden options of our own.
- Every island page: Cmd+R refreshes its data, Cmd+P pins the island.
- Unused upstream features are hidden, never cut: off and gone from Settings, search and launcher, code kept; the list is only [notchcast/docs/hidden.md](../notchcast/docs/hidden.md).
- Rebrand only what is visible (command names, About, onboarding, menu bar); keep `LICENSE`, `NOTICE.md` and the `.tinycast` backup type.

## Current

- `main` is upstream `main` plus our commits, replayed and tested by Sync ([notchcast/README.md](../notchcast/README.md)); PRs land only through `notchcast/land.sh`.

## Next

- Kept in the maintainers' tracker, not here.

## Log

- Landings are the squash commits on `main` (`git log --first-parent main`); nothing is copied here.
