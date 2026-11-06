# Contributing to Notchcast

Notchcast is upstream [Tinycast](https://github.com/abue-ammar/tinycast) plus our commits on top, replayed onto every new upstream `main`. Everything here serves one rule: our commits must keep rebasing cleanly onto upstream.

## Where a change belongs

- A bug or feature in upstream's code (launcher, clipboard, snippets, window management, AI chat, ...): report or fix it in [Tinycast](https://github.com/abue-ammar/tinycast). It reaches Notchcast with the next sync.
- A bug or feature in Notchcast's own features (island, the Settings → Notchcast tabs, our launcher commands) or in packaging and updates: open an [issue here](https://github.com/kaczordodgers/notchcast/issues/new/choose).

## Pull requests

1. Branch off current `main`. Build and test as in the [README](/README.md#build-from-source).
2. Put new code in new files under `Tinycast/Features/<Feature>/`. Touch as few upstream files and lines as possible, and only by adding lines.
3. Do not commit generated files: `Tinycast.xcodeproj/project.pbxproj`, `README.md` (edit `notchcast/README.public.md`) and `Tinycast/Resources/RaycastRuntime.generated.js`. CI regenerates them.
4. Follow upstream's [AGENTS.md](/AGENTS.md), [docs/standards.md](/docs/standards.md) and [docs/ui.md](/docs/ui.md): no third-party dependencies, upstream's design system and wording, all eight translations.
5. Add a runnable harness (`Tests/nc-<Feature>-<name>-test.swift`) for non-trivial logic.
6. List every upstream file you touched in the PR description.

Maintainers land PRs with `notchcast/land.sh`, which squash-merges after the checks pass. The full process is in [notchcast/README.md](/notchcast/README.md).

## License

Contributions are released under the [GNU Affero General Public License v3.0 or later](/LICENSE), the same as Tinycast.
