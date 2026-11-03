# Notchcast

**Notchcast** is a fork of [Tinycast](https://github.com/abue-ammar/tinycast) (AGPL-3.0): upstream `main` plus a few commits of ours on top, arm64 builds signed with our own identity. Upstream's README is [README.upstream.md](README.upstream.md).

Every ~10 minutes a GitHub Actions workflow replays our commits onto the newest upstream `main`, builds and runs the tests, and moves `main` only when green; each upstream release is rebuilt the same way and published here under the same tag.

This file is `notchcast/README.md`; the sync copies it to the root `README.md`. `main` is the default branch. Feature work happens on branches off `main` and lands as linear commits (no merge commits). Features are our own code; Notchcast uses no Raycast extensions.

Our commits:

- `Notchcast: read releases from kaczordodgers/notchcast`: the in-app updater reads this repo's releases.
- `Notchcast: remove upstream workflows`: none of upstream's workflows run here. The sync makes this commit afresh on every replay, so upstream workflow edits never conflict and new ones never land.
- `Notchcast: let a LaunchAgent own starting the app`: with `NOTCHCAST_LAUNCHD=1` the app keeps its login item off and its Relaunch only quits, so the LaunchAgent below is the only thing that starts it.
- `Notchcast: tooling` and later fixes: this folder and `.github/workflows/`.
- `Notchcast: bundle id app.notchcast, URL scheme notchcast, name Notchcast`: our own app identity (Debug: `app.notchcast.dev`). The in-app updater treats it as a development build and stays inert; `notchcast.update` installs releases.
- `Notchcast: generated files`, always last: the root `README.md` (this file), `README.upstream.md` (upstream's README with a one-line note), `Tinycast.xcodeproj` (XcodeGen from `project.yml`) and, when our commits change `Scripts/raycast-runtime/`, `Tinycast/Resources/RaycastRuntime.generated.js`. The sync makes it afresh; our other commits never carry these files (replay drops them from each commit), so upstream edits to them never conflict. Edit `notchcast/README.md` or `project.yml`, never the generated files.

## Sync (`.github/workflows/sync.yml`)

- Every 10 minutes (and on a push to `main` or a manual run): if upstream `main` moved, the plan job first replays our commits on Linux; a conflict is reported there without spending a macOS runner. Then `notchcast/ci.py replay` cherry-picks our commits (`merge-base(main, upstream/main)..main`) onto the new upstream `main`, builds Debug on a GitHub-hosted `xcode-27` runner and runs upstream's `Scripts/run-tests.sh`. Only when green does it update `main` with `--force-with-lease` on the `main` it started from. That workflow push is the only history rewrite allowed in this repo; nobody force-pushes by hand. A `main` commit without a green `notchcast/tested` status (a push) is built and tested as it is, and gets that status when green.
- Every upstream release from `BASELINE_TAG` (`config.env`) on is rebuilt from its tag with our commits replayed onto it, tested, built Release for arm64, signed with `Notchcast Self-Signed` and published under the same tag, title and prerelease flag as `Notchcast-<version>.zip` and `.dmg`. Version and build number come from upstream's own zip; there is no version of our own. Upstream's tag is mirrored unchanged.
- Tests: upstream's full suite except `CI_SKIP_TESTS` (`config.env`), harnesses the hosted VM cannot run (Vision OCR, rendered-text capture), which must still pass on a Mac. A harness that fails is run once more alone; if it still fails, it is run on the pristine upstream commit under our commits, and only a harness that passes there blocks (a failure on upstream too is upstream's flake or the VM, and is ignored with a warning).
- On a replay conflict, a red build or a red test nothing is pushed or published and `main` stays as it is. A red build or test is remembered as `refs/notchcast-failed/<main-<upstream>|release-<tag>|test>-<main>`, so it is retried only when upstream or `main` changes; a conflict is found again cheaply on Linux each run.
- Each failure opens or updates one issue per kind, closed by the next green run of that kind: `notchcast-sync` (replaying onto new upstream), `notchcast-main` (a pushed `main` tested as it is), `notchcast-release` (per tag). A conflict's issue names our commit and files and lists the upstream commits that touched them. A cause that stays the same (the same conflict, the same red `main`, the same tag) on a newer upstream only retitles the issue. The updater on the MBA tells Chad once per issue and cause (`chad-opus ping failure`).
- A sync that brings upstream changes under `Tinycast/DesignSystem/`, to `Theme.swift` or to `docs/ui.md` opens one `notchcast-design` issue listing those upstream commits; the updater on the MBA turns it into one Todoist task (label `notchcast`), "Refresh notchcast/docs/design-system.md", and closes it.

## Secrets and checks

- Actions secrets live in the environment `sync`, which only `main` may use: `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD` (the self-signed code-signing identity) and `DEPLOY_KEY` (write deploy key `notchcast-actions`; `GITHUB_TOKEN` cannot push commits that touch workflow files). The same material is kept outside git on the maintainer's Mac. The public leaf fingerprint is `SIGN_SHA1` in `config.env`.
- `.github/workflows/leaks.yml` and the hooks in `notchcast/githooks` run gitleaks and `check-identity.sh` (no employer name in files, commit messages or commit identities). Per clone, before the first commit: `git config core.hooksPath notchcast/githooks`, a repo-local `user.email` noreply address, and `git remote set-url --push upstream DISABLED`.
- Commits made by the workflow are committed as `github-actions[bot]`.

## Installing on a Mac

`notchcast/install-launchd.sh all` once per Mac; logs are in `~/Library/Logs/notchcast/`. It:

1. installs the newest release at `/Applications/Notchcast.app` (`update.sh`);
2. copies the old Tinycast Beta data once (`migrate.sh`), each part only while the Notchcast side is still empty: preferences (`defaults export com.tinycast.app.beta | defaults import app.notchcast`), `~/Library/Application Support/com.tinycast.app.beta/` and `~/.config/tinycast-beta/settings.json` (to `~/.config/app.notchcast/`). The old data is never changed. Keychain secrets (keyed by bundle id) are not copied;
3. quits Tinycast Beta and moves its `.app` to the Trash;
4. loads the two LaunchAgents:
   - `notchcast.app` runs `/Applications/Notchcast.app` itself: started at login, restarted after a crash or a Quit (`KeepAlive`, at most every 10 s), with `NOTCHCAST_LAUNCHD=1`. Stop: `launchctl bootout gui/$(id -u)/notchcast.app`. Start: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/notchcast.app.plist`.
   - `notchcast.update` runs `update.sh` every 30 minutes (needs `gh` logged in): the newest release is installed when it is newer, or when the installed copy is not ours, after checking bundle id, version and our leaf certificate; the old `.app` goes to the Trash and `notchcast.app` is restarted with `launchctl kickstart -k`. Settings, data and Keychain items are never touched.

The new bundle id and signature need Accessibility to be granted once.
