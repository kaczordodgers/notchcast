# Tinycast: how features ship, feature inventory, hooks and identity surfaces (for the Notchcast patch queue)

Source: read-only clone of upstream `abue-ammar/tinycast`, HEAD `3be769dc` (903 commits). Paths are relative to the clone root. Line numbers are as of that HEAD. No builds were run.

## 1. How the author ships a feature

### Template commits

| Commit / PR | What | Files (excl. `.xcstrings`) | Tests | Docs | Settings / UI wiring | README / website |
| --- | --- | --- | --- | --- | --- | --- |
| `3be769dc` #1781 Move-to-edge window commands | 4 new window commands | 8 files, +321/−24 | `Tests/window-command-test.swift` +70 | `docs/features/window-management.md`, `docs/features/settings-file.md` (count 35→39) | Only a pure-model change: `WindowCommand.swift` cases + `WindowPlacementEngine.swift`. The new cases flow through existing registries with no wiring | `README.md` count bump, `website/content/docs/features/window-management.md` |
| `95ecb016` #1766 AI "Expand thinking" setting | One boolean preference | 18 files, +147/−8 | `Tests/ai-provider-test.swift` +3 | `docs/features/ai.md` | `AISettingsStore` property, `AISettingsView` toggle, `AppSettingsKey`, `SettingsFileKey` + `SettingsFileSchema` binding, `SettingsSearchCatalog` row, `SettingsBackupCoverage` (excluded from backups) | `website/content/docs/reference/settings.md` |
| `2dbd7dae` #1719 Notes menu bar item | New controller + opt-in toggle | 16 files, +206 | `Tests/settings-backup-test.swift` +3 | `docs/features/notes.md`, `docs/testing.md` (manual sweep) | New `NotesMenuBarController.swift` (and pbxproj entries), `AppCore.swift` `track(...)` +2, `AppSettings` property + init, `AppSettingsKey`, `SettingsFileKey`, `SettingsFileSchema`, `SettingsSearchCatalog`, `SettingsBackup` + `Coverage`, `NotesSettingsView` toggle | none |
| `b04ab81f` #1720 File/folder favorites in launcher | Cross-feature behaviour | 18 files, +450/−164 | `Tests/file-search-test.swift`, `Tests/app-installation-test.swift`, new harness registered in `Scripts/run-tests.sh` | `docs/features/file-search.md`, `launcher.md`, `testing.md` | New `FavoriteActions.swift`, `project.yml` + pbxproj, edits across Launcher and FileSearch UI | none |
| `fb7abf3a` #1692 Show animations toggle | App-wide setting | ~40 files | `Scripts/run-tests.sh` +3 | `docs/architecture.md`, `ui.md` | `AppCore.applyMotion()` + `track`, `Motion.swift`, new `AnimatedPanel.swift`, every panel touched, the usual 6 settings registries | none |
| `c3857b06` #1680 AI custom request headers | New model + Keychain scope | 16 files, +757/−64 | `Tests/ai-provider-test.swift` +58 | `docs/features/ai.md` | New `Model/AIRequestHeaders.swift` (pbxproj), editor panel UI; deliberately **not** in `AIConnection`, so backups and `settings.json` stay untouched | `website/content/docs/ai/index.md` |

### The common recipe (what upstream does every time)

1. **An approved issue first.** The PR body says `Closes #N`; the `issue-link.yml` bot closes PRs that have no linked issue after 24 h. #1781 closes #1775. The PR template asks for memory numbers (idle/peak, under 100 MB) and a before/after video for visual changes.
2. **Model first, under `Features/<X>/Model/`.** Pure Foundation code with injected environment, so a `Tests/<x>-test.swift` harness can compile it directly. The test is extended in the same commit.
3. **A new preference touches 6–7 fixed registries:** `AppSettings.swift` (property + `init` read), `AppSettingsKey.swift` (`UserDefaults` key), `Model/SettingsFileKey.swift` + `SettingsFileSchema.swift` (an exhaustive switch makes the build fail until it is bound), `SettingsSearchCatalog.swift` (row + keywords; `lint.sh` checks it), `Backup/Model/SettingsBackup.swift` + `SettingsBackupCoverage.swift` (include or exclude from backups), the pane view, and an `AppCore.observeFeatureSwitches()` `track(...)` if it must re-apply live.
4. **New files mean pbxproj churn.** `Tinycast.xcodeproj` is committed but generated from `project.yml` (`xcodegen generate`). `project.yml` takes all of `Tinycast/`, so any new file changes `project.pbxproj`.
5. **Localization in the same commit.** `Localizable.xcstrings` is updated for all 8 languages (`./Scripts/sync-strings.sh`; `check-localizations.js` runs from lint). This is the largest file in most diffs.
6. **Docs:** `docs/features/<x>.md` is always updated (each file starts with its invariants), plus `docs/testing.md` for manual-sweep items. README and `website/content/docs/...` change only when user-visible counts or behaviour change.
7. **No CHANGELOG file.** Release notes come from GitHub's release-notes API over merged PR titles (`Scripts/release-notes.sh`, `docs/release.md:100`), so the PR title is the changelog line.
8. **Commit style:** imperative subject; the body explains behaviour and defaults ("Off by default", "kept out of backups"); squash-merged with the PR number.

## 2. Build, test, CI and conventions

- **Build** (`docs/development.md:33`, `docs/testing.md:248`): `xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build` (`CODE_SIGNING_ALLOWED=NO` for a check build). Debug produces `Tinycast Dev.app`, bundle id `com.tinycast.app.dev`, URL scheme `tinycast-dev`. Upstream signs with the identity "Tinycast Self-Signed" (`project.yml:18`, `docs/signing.md`); our Debug signs ad-hoc so headless Xcode builds anywhere, and a local Debug run loses its Accessibility grant on each rebuild unless built with `CODE_SIGN_IDENTITY="Tinycast Self-Signed"`. Release is unchanged.
- **Tests:** `./Scripts/run-tests.sh [name]` (1018 lines). There is no XCTest. `Tests/` holds about 130 standalone Swift files, each a `main`-style harness. The runner compiles each harness with `swiftc -swift-version 6` together with the **shipped source files it lists**, so an upstream harness is registered by adding a `run [slow|exclusive|-O|index] <name> <sources…>` line (122 such lines, from `Scripts/run-tests.sh:119`). It runs 4 at a time (`TINYCAST_TEST_JOBS`) with a 300 s timeout (`TINYCAST_TEST_TIMEOUT`). `onboarding-test` runs alone and needs an unlocked desktop. Runtime JS fixtures: `node Scripts/raycast-runtime/{modules,oauth}-fixtures.mjs`.
- **Lint:** `./Scripts/lint.sh` runs swiftlint, `check-settings-search.js`, `check-localizations.js` and `check-migrations.sh`. Format: `Scripts/format.sh`.
- **Definition of done** (`docs/testing.md` "Definition of done"; `AGENTS.md` "Before you finish"): harnesses pass, lint is clean, the purity grep `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` returns nothing, the Debug build has zero **new** warnings, and docs are fixed in the same commit.
- **CI gates nothing on code.** `CONTRIBUTING.md` and `testing.md` both say "There is no CI". The workflows:
  - `coauthors.yml`, `issue-link.yml`, `triage.yml`: PR and issue bots (`pull_request_target`). These are the `check`/`triage` checks seen on #1781, plus the CodeRabbit review.
  - `release.yml`: `workflow_dispatch`, `xcode-27` runner. Runs `check-migrations.sh`, signs with the p12 secret, verifies the signature, builds a universal app, pushes the Homebrew cask, posts to Discord and triggers `website.yml`.
  - `website.yml`: on push to `main` under `website/**`, deploys to Cloudflare and Pages.
  - `gitlab-mirror.yml`: on push to `main`, mirrors to GitLab.
  - **For the fork, disable all six.** They would fail without secrets or would act on the wrong identity (section 5).
- **Conventions that matter for patches** (`AGENTS.md`, `docs/standards.md`):
  - `AppCore` is the sole owner; new long-lived state is wired in `start()`.
  - `Model/` files never import AppKit or SwiftUI.
  - Swift 6 strict concurrency; synchronous `@MainActor` is preferred.
  - No `NSAlert` (use `DialogController`/HUD).
  - Networked features use a private ephemeral `URLSession`.
  - Extensions stay inside `Features/Extensions/`.
  - `AppEntry.Kind` is the single source of entry category, and `SettingsTab.ownedCommands` the single source of pane ownership.
  - Generated files are never hand-edited.
  - `EdgeDissolve.swift` and `ThinScrollbar.swift` are off-limits.
  - Comments are rare, one line, 100 characters at most.
  - Migrations live only in `Tinycast/Migrations/` and are deleted after one release.
  - Everything persisted is keyed by `Bundle.main.bundleIdentifier`.

## 3. Feature inventory

### Key fact for the hide/cut decision

Every feature switch except Clipboard **already defaults OFF.** `AppSettings.init` reads `defaults.bool(...)`, so a missing key is `false` (`Tinycast/Features/Settings/AppSettings.swift:769–906`). The switches that default ON are:

- `clipboardEnabled` (`:686`)
- `animationsEnabled` (`:762`)
- `automaticallyCheckForUpdates` (`:705`)
- `supportRemindersEnabled` (`:903`)

A disabled feature takes its launcher commands down with `appIndex.setCommandsVisible(…, enabled)`, called from the feature's `applyEnabled()` in `AppCore.start()` (`Tinycast/App/AppCore.swift:301–359`) and re-applied live from `observeFeatureSwitches()` (`AppCore.swift:674–794`).

### Why cutting is expensive

A feature is registered in shared **exhaustive** enums: `CommandID` (5 `switch self` blocks, `Tinycast/Features/Launcher/Model/CommandID.swift`), `PaletteMode` (`Tinycast/Palette/PaletteMode.swift:3`), `SettingsTab` (3 switches, `Tinycast/Features/Settings/SettingsTab.swift:1`), `AppEntry.Kind` (`Tinycast/Features/Launcher/Service/AppIndex.swift:4`), `SettingsFileKey`, `AppSettingsKey` and `HotKeyAction`. It also sits in `LauncherCoordinator.runCommand` (`Tinycast/Features/Launcher/UI/LauncherCoordinator.swift:166`), `RootPaletteView`, `AppCore` lazy vars (`AppCore.swift:89–241`), `Tests/` + `Scripts/run-tests.sh` and pbxproj.

So **no feature is cleanly cuttable at low conflict risk**. Recommended policy: cut nothing; hide or disable everything with 1–3 line patches.

### How N is counted

N = the number of files outside the feature folder that reference the folder's types (script `work-ship/coupling.py`, full list in `work-ship/coupling.txt`), plus the enum and flag sites named in the row. Sizes are Swift files and `wc -l` lines in the folder (`work-ship/sizes.txt`).

### Feature table

| Feature (doc) | What | Size | Registration points (path:line) | Default | Verdict |
| --- | --- | --- | --- | --- | --- |
| AI (`ai.md`) | Quick AI palette chat, AI Chat window, providers (HTTP, Codex, installed CLIs, Apple Intelligence) | `Features/AI` 99 files / 20,631 | `AppCore.swift:73–82,232–238,312`; `AppSettings.swift:416,813`; `CommandCatalog.swift:57`; `AIChatCoordinator.swift:37`; `RootPaletteView` (10 refs); `PaletteMode` `.ai`/`.aiHistory`; used by QuickActions and MCP | off (`aiEnabled`) | **Hide** (already off). Cut N≈22 files + QuickActions/MCP depend on it |
| Apple Shortcuts (`apple-shortcuts.md`) | Lists and runs Shortcuts.app shortcuts in the launcher | 4 / 253 | `AppCore.swift:161,342,397`; `AppSettings.swift:631,896`; `AppIndex.swift` `.appleShortcut` Kind; `HotKeyAction+EntryID.swift`; `HotKeyManager`; `LauncherCoordinator` | off | **Hide** (already off). Cut N=6 + Kind case + SettingsTab case |
| Backup (`backup.md`) | `.tinycast` export/import file | 19 / 2,994 | `CommandID` `.exportSettings`/`.importSettings`; `Info.plist:45` UTType; `SettingsTab.backup`; `OnboardingView`; `LauncherCoordinator`; `QuicklinkCoordinator`; every new pref touches `SettingsBackup*` | always on | **Keep** (cross-cutting). Hide commands via hook H1 if unwanted |
| Calculator (`calculator.md`) | Inline calculator, units, currency, history | 33 / 6,315 | `AppCore.swift:50–51,202,357` (`currencyRates.start()` fetches network rates); `LauncherScreen` (5); `LauncherList`; `RootPaletteView`; `PaletteMode.calculatorHistory`; `AppSettings` | always on, **no switch** | **Disable via small patch** (gate in `LauncherScreen`, ~3 lines + skip `currencyRates.start()`). Cut N=9 + 2 enum cases |
| Calendar (`calendar.md`) | Join card, schedule, events, calendar menu bar, auto-join | 27 / 2,681 | `AppCore.swift:53,204,355,751`; `TinycastApp.swift:25` (second `MenuBarExtra`); `LauncherScreen` (7); `LauncherList` (6); `RootPaletteView` (5); `CommandCatalog.swift:66–67`; `AppIndex` `.meeting`; `PaletteMode.schedule`/`.eventEditor`/`.meetingDetails` | off | **Hide** (already off). Cut N=11 + 3 PaletteMode + Kind + 5 CommandIDs |
| Camera (`camera.md`) | Live camera preview, photo to clipboard | 6 / 494 | `AppCore.swift:217`; `CommandID.openCamera` (`CommandID.swift:19`); `Calendar/UI/CameraPreview*` use `CameraSession` | always listed, **no switch** | **Hide via hook H1** (`setCommandsVisible([.openCamera], false)`). Cut N=3 + 1 CommandID (Calendar depends on it) |
| Clipboard (`clipboard.md`) | Text/image clipboard history, paste sequentially, OCR helper | 25 / 4,114 | `AppCore.swift:20,195,271,302`; `ClipboardCoordinator.swift:40`; `project.yml` `ClipboardTextHelper` target; 46 external files | **ON** | **Keep, or disable via 1-line default flip** (`AppSettings.swift:686`). Not cuttable (N=46) |
| Custom Commands (`custom-commands.md`) | User shell commands with args/output in the launcher | 15 / 2,667 | `AppCore.swift:11,156,319–322,379`; `AppSettings.swift:420,815`; `CommandCatalog.swift:54`; `AppIndex` `.customCommand`; `DeepLinkCoordinator`; `HotKeyAction+EntryID`; `PaletteMode.customCommands`/`.customCommandEditor` | off | **Keep. This is plug-in hook H2** |
| Deeplinks (`deeplinks.md`) | `tinycast://command/…` etc. URL control with ask-once consent | 7 / 793 | `AppCore.swift:239,491` (`handleOpenURL`); `AppSettings.swift:667`; `GeneralSettingsView`; `Info.plist:23–33` scheme | always on | **Keep (hook H3)**; rename the scheme in `project.yml:22,26` |
| Dictation (`dictation.md`) | Local speech-to-text through a helper app | 26 / 2,912 | `AppCore.swift:30,33,95,293,373–377,402`; `AppSettings.swift:351,780`; `SettingsFileSchema` (5); `project.yml` `DictationHelper` target + dependency; `AIChatDetailView`/`AIChatCoordinator` | off | **Hide** (already off). Cut is costly: N=6 + helper target in `project.yml` |
| Dictionary (`dictionary.md`) | "Define Word" command and fallback | 7 / 644 | `AppCore.swift:64,218`; `RootPaletteView` (2); `PaletteMode.dictionary`; `CommandID.define`; fallback builtin in `FallbackCoordinator.swift:70` | always on, **no switch** | **Hide via H1** + user fallback settings. Cut N=2 + PaletteMode + CommandID + Fallback case ≈ 6 sites |
| Emoji (`emoji.md`) | Emoji and symbols grid picker | 10 / 3,524 (+ generated data) | `AppCore.swift:58–59,199,297,358`; `RootPaletteView` (9); `PaletteState` (4); `AppSettings`; `SettingsBackup`; `RaycastImportReader`; `CommandCatalog.swift:65`; `CommandID.defaultCompactBarCommands` | always on, **no switch** | **Hide via H1** (`.searchEmoji`) + compact bar default. Cut N=10 |
| Extensions (`extensions.md`) | Runs Raycast extensions in JavaScriptCore; store, GitHub install, menu bar extras | 78 / 14,549 + `Resources/RaycastRuntime.generated.js` + `Scripts/raycast-runtime` | `AppCore.swift:133,273,303–304,410`; `RootPaletteView` (10); `AppSettings.swift:467,827`; `LauncherCoordinator`; `AppIndex` `.extensionCommand`; `PaletteMode.extensionCommand`; `DesignSystem/InlineArgumentFields.swift` | off | **Hide** (already off). Keep as plug-in hook H4 |
| File Search (`file-search.md`) | Own filename index (FSEvents) and search screen | 24 / 3,418 | `AppCore.swift:63,207,305,308`; `FileSearchCoordinator.swift:33`; `FavoritesStore`; `LauncherScreen`/`List`; `project.yml` `FileIndexHelper` target | off | **Hide** (already off). Cut N=11 + helper target |
| Hotkeys (`hotkeys.md`) | Global/per-app chords, Hyper Key, modifier taps | 33 / 4,377 (Hyper Key 9 / 1,441) | `AppCore.swift:27,31,370–440`; 50 external files | core | **Keep** (core). Hyper Key is off unless configured |
| Launcher (`launcher.md`) | App index, ranking, favorites, aliases, fallbacks, compact bar | 45 / 6,149 | core; 100 external files | core | **Keep** |
| MCP (`mcp.md`) | MCP servers' tools offered to AI chat | 22 / 2,874 | `AppCore.swift:76–78,229,313`; `AppSettings.swift:413,814`; `AIChatCoordinator` (5); `AISettingsView` | off | **Hide** (already off). Cut N=3, but it imports AI types; the cleanest of the large features |
| Menu Search (`menu-search.md`) | Search the frontmost app's menu bar items | 11 / 856 | `AppCore.swift:65,211,307,348`; `MenuSearchCoordinator.swift:30`; `LauncherCoordinator`; `PaletteCoordinator`; `RootPaletteView`; `PaletteMode.menuSearch` | off (`navigationEnabled`) | **Hide** (already off). Cut N=4 + PaletteMode + CommandID |
| Navigation (`navigation.md`) | Switch Windows, Switch Windows Backwards, Menu Search behind one switch | `Features/WindowSwitcher` 10 / 560 | `AppCore.swift:66,214,306,349`; `WindowSwitchCoordinator.swift:28`; `AppSettings.swift:451,874`; `CommandCatalog.swift:62` | off | **Hide** (already off). Cut N=4 + PaletteMode + 2 CommandIDs |
| Notes (`notes.md`) | Floating Markdown notes editor, switcher, menu bar item | 36 / 5,639 | `AppCore.swift:167,279,309,725,794`; `AppSettings.swift:347,779`; `NotesCoordinator.swift:102`; `QuickActionCoordinator`; `DeepLinkCoordinator`; `PaletteWindowController`; `BackupApplier` | off | **Hide** (already off). Cut N=7 + 3 CommandIDs |
| Palette (`palette.md`) | Floating panel shell, compact/expanded modes | `Tinycast/Palette` 22 / 4,277 | core | core | **Keep** (core) |
| Quick Actions (`quick-actions.md`) | AI actions on selected text (Fix Grammar, Rewrite, Translate, Summarize, custom) | 19 / 2,292 | `AppCore.swift:79–80,224,314–319`; `AppSettings.swift:438,821`; `CommandID.swift:5–8` + switches; `CommandCatalog.swift:58`; `AppIndex` `.quickAction` | off | **Hide** (already off). Cut N=7 + 4 CommandIDs + Kind |
| Quicklinks (`quicklinks.md`) | URL/search/file templates as commands | 14 / 2,457 | `AppCore.swift:12,110,336–341`; `QuicklinkCoordinator.swift:68`; `CommandCatalog.swift:55–56`; 24 external files | off | **Keep (hook H5)**. Not cuttable |
| Raycast import (`raycast-import.md`) | Reads a `.rayconfig` export | in `Features/Backup`, 5 / 499 | `CommandID.importFromRaycast`; Backup UI | always listed | **Hide via H1** |
| Settings file (`settings-file.md`) | Opt-in `~/.config/tinycast/settings.json` mirror | 11 / 1,295 | `AppCore.swift:416–418`; `AppSettings.swift:662,906`; `AppPaths.swift:57–60` (folder name) | off | **Keep** (every new pref must bind here, see recipe step 3) |
| Snippets (`snippets.md`) | Markdown text templates with keyword expansion | 16 / 3,591 | `AppCore.swift:89,274,443–455,774,793`; `SnippetCoordinator.swift:101`; `AppSettings.swift:433,820`; 23 external files | off | **Hide** (already off). Not cuttable |
| Support (`support.md`) | Donation window (Polar checkout) + 30-day reminder | 4 / 261 | `AppCore.swift:56,222,268,364–365,486`; `MenuBarItem.swift:28`; `LauncherCoordinator.swift:269`; `CommandID.swift:49,124,174`; `AppSettings.swift:657,903`; `AppSettingsKey.swift:119`; `SettingsFileKey.swift:12`; `SettingsFileSchema.swift:39`; `SettingsSearchCatalog.swift:676`; `AboutView` | **ON** (reminder) | **Disable via small patch**: flip `AppSettings.swift:903–905` to default off, hide `.support` (H1), drop `MenuBarItem.swift:28`. Cut N≈14 sites |
| Uninstall (`uninstall.md`) | Remove an app and its leftovers | 11 / 1,417 | `AppCore.swift:68,129`; `RootPaletteView` (2); `PaletteMode.uninstall`; launcher Actions menu | always on | **Keep or hide** the action-menu row (~1 line). Cut N=2 + PaletteMode + menu row |
| Updates (`updates.md`) | Daily GitHub Releases check and self-install | 16 / 1,414 | `AppCore.swift:55,220,354,358–361,470–472`; `MenuBarItem.swift:27`; `ReleaseFeed.swift:15`; `ReleaseChannel.swift:10–14`; `AppleShortcutRunner` (3); `RootPaletteView.swift:218` | ON, but **inert for a non-`com.tinycast.app[.beta]` bundle id** (`ReleaseChannel` → `.development`) | **Disabled for free** by renaming the bundle id. Drop menu row `MenuBarItem.swift:27` (1 line). Do not cut |
| Window layouts (`window-layouts.md`) | Saved multi-app arrangements | in `WindowManagement`, 17 / 2,257 | `AppCore.swift:13,146,329–332`; `WindowLayoutCoordinator.swift:47`; `AppIndex` `.windowLayout` | off | **Hide** (already off) |
| Window management (`window-management.md`) | 39 Rectangle-style commands, custom sizes, presets | `Features/WindowManagement` 62 / 8,977 | `AppCore.swift:14,136–145,324–328`; `AppSettings.swift:581,878`; `AppIndex` `.windowCommand`; 22 external files | off | **Hide** (already off). Not cuttable |
| Window rooms (`window-rooms.md`) | Named window sets you "enter" (MIT, adapted from saragordic/rooms) | in `WindowManagement`, 23 / 3,165 | `AppCore.swift:15–19,151,333–335`; `RoomCoordinator.swift:68`; `PaletteMode.rooms`/`.roomWindows`; `AppIndex` `.windowRoom` | off | **Hide** (already off) |
| *System Actions (no doc)* | Volume, mic mute, lock screen, etc. as commands | 8 / 1,112 | `AppCore.swift:127,383,437`; `SettingsTab.systemActions`; `AppIndex` `.systemAction`; 15 external files | listed | **Keep or hide** with per-item `VisibilityStore` checkboxes (user data, no patch) |
| *Text Injection (no doc)* | Paste/type into the frontmost app (used by snippets, dictation, AI) | 4 / 1,282 | 11 external files | infrastructure | **Keep** |
| *Onboarding (no doc)* | First-launch window | 4 / 537 | `AppCore.swift:125,462–464`; `OnboardingView` uses Backup | first launch | **Keep or rebrand** (shown once; text says "Tinycast") |
| *Settings (no doc)* | Settings window, panes, search catalog | 32 / 4,735 | core; 84 external files | core | **Keep**. Hide sidebar panes with a 1-line edit of `SettingsTab.swift:114–130` (`SettingsSection.tabs`) |
| *About window (no doc)* | Credits and links | `Windows/About` 1 / 213 | `AboutView.swift:148–163` | n/a | **Rebrand** (section 5) |

## 4. Plug-in hooks for Notchcast's own features (fewest upstream files touched)

Ranked from least to most upstream contact.

1. **H4 Raycast extension (0 upstream files).** Write our feature as a Raycast-API extension (`package.json` + CommonJS bundle) and install it with Install from GitHub or a local import (`docs/features/extensions.md:487–525`). Extensions get commands, list/detail/form UI, menu bar extras, background refresh, hotkeys, aliases and deeplinks. Limits: it runs in JavaScriptCore (no native AppKit), and the "Extensions stay inside Features/Extensions" rule means no access to launcher surfaces. Best for anything that is data or UI-list shaped.
2. **H2 Custom Commands / H5 Quicklinks / Apple Shortcuts / Snippets (0 upstream files, user data).** A shell script, URL or Shortcut becomes a launcher row with a hotkey and deeplink (`docs/features/custom-commands.md`). Best for glue around external tools (e.g. our CLIs).
3. **H3 Deeplinks (0 files).** External processes such as Karabiner, launchd or scripts drive the app through `notchcast://command/<slug>`, `window-command/…`, `system-action/…` (`docs/features/deeplinks.md:67–74`; dispatch `AppCore.swift:491`).
4. **H1 One "Notchcast policy" call in `AppCore.start()` (1 upstream file, ~3 lines).**
   - Add `appIndex.setCommandsVisible([.openCamera, .define, .searchEmoji, .importFromRaycast, .support, .calculatorHistory], false)` after the `applyEnabled()` block (`AppCore.swift:301–359`).
   - `AppIndex.setCommandsVisible` (`Tinycast/Features/Launcher/Service/AppIndex.swift:429`) is a set union, and none of those commands is re-toggled by any coordinator (the only togglers are listed in `work-ship` grep: Snippets, CustomCommands, MenuSearch, Calendar, WindowSwitch, Updates, FileSearch, Quicklinks, Notes, AI, QuickActions, WindowLayout, Room, Clipboard). So the call sticks.
   - Better still, keep our code in a new file `Tinycast/Notchcast/NotchcastPolicy.swift`, called by **one line** in `start()`. The patch is then 1 line in AppCore plus a new file and its pbxproj entries.
5. **H6 A native feature folder `Tinycast/Features/<Ours>/` (≈4–6 upstream files).**
   - Lazy coordinator on `AppCore` (`AppCore.swift:89–241`) plus a `start()` line.
   - A `CommandID` case with entries in its exhaustive `name`/`sfSymbol` switches (`CommandID.swift:3,78,129`) and in `LauncherCoordinator.runCommand` (`LauncherCoordinator.swift:166`).
   - Optionally a `PaletteMode` case plus a `RootPaletteView` branch for a palette screen, or a `SettingsTab` case (3 switches) for a pane.
   - A preference costs the 6–7 settings registries from section 1, step 3.
   - Conflict hotspots: `CommandID.swift`, `AppCore.swift` and `project.pbxproj`, all edited by about every second upstream feature.
   - Mitigation: add command cases at the **end** of the enum and of each switch.
   - Mitigation: regenerate pbxproj locally with `xcodegen generate` after each rebase and leave it uncommitted, or keep our sources in a separately grouped folder so the pbxproj hunks are isolated.
6. **Avoid:** adding `AppEntry.Kind` cases (forces `KindDescriptor` and `VisibilityStore` changes), editing `DesignSystem/`, and new settings keys unless needed.

## 5. Identity and branding surfaces

Upstream contains no reference to the maintainer's employer, so nothing needs removing. The risk is **introducing** one:

- A machine's global git identity may be a work address. Every Notchcast commit author line and `Co-Authored-By` would carry it, so each clone sets a repo-local noreply `user.email`.
- Do not use an employer bundle id prefix, signing identity, URL or domain anywhere below.

### Rebrand surfaces

| Surface | Where (path:line) | Fork action |
| --- | --- | --- |
| Bundle id + prefix | `project.yml:3` (`bundleIdPrefix: com.tinycast`), `:20` (`com.tinycast.app`), `:24` (`.dev`); helper ids derive from it (`project.yml` `DictationHelper` `$(TINYCAST_BUNDLE_IDENTIFIER).dictation`) | Change the 3 values. This also disables the updater (below) and separates prefs, caches, Keychain and TCC from any installed Tinycast |
| Fallback ids hard-coded in Swift | `Platform/AppPaths.swift:6,12,19,30,43,57`; `KeychainSecretStore.swift:19`; `LauncherRankingStore.swift:159`; `SnippetRepository.swift:115`; `ExtensionCatalog.swift:94`; `CustomQuickActionStore.swift:20`; `QuicklinkStore.swift:49`; `ClipboardStore.swift:320` (only used if `bundleIdentifier` is nil) | Leave as is (inert). Exception: `AppPaths.swift:57–60` maps only `com.tinycast.app` to `~/.config/tinycast`; any other id becomes the folder name itself, which is acceptable |
| Own-app detection | `AppIndex.swift:819` `ownBundlePrefix = "com.tinycast."` (hides our own app from the launcher) | 1-line patch to the new prefix, otherwise Notchcast lists itself |
| Update channel / feed | `Features/Updates/Model/ReleaseChannel.swift:10–14` (`com.tinycast.app` = stable, `.beta`); `ReleaseFeed.swift:15` (`abue-ammar/tinycast`); `UpdateCheckStore.swift:8` (GitHub releases API); `ReleaseNotes.swift:104` | A new bundle id makes `.development`, so no checks and no install (`UpdateCheckStore.swift:74`), with no patch. **Must** be done, or Notchcast would offer to replace itself with upstream Tinycast. There is no Sparkle or appcast |
| Signing identity | `project.yml:18` `CODE_SIGN_IDENTITY: "Tinycast Self-Signed"`; `Scripts/build-dmg.sh:7`; `release.yml:90,105,318`; `docs/signing.md` | Own self-signed identity name for Release; Debug signs ad-hoc (`CODE_SIGN_IDENTITY: "-"`), losing the Accessibility grant on each local rebuild unless `CODE_SIGN_IDENTITY="Tinycast Self-Signed"` is passed. No team id (`DEVELOPMENT_TEAM: ""`, `project.yml:15`) |
| Notarization | None. Releases are self-signed with `--timestamp=none` (`release.yml:106,319`); "Assert the signature is notarizable" (`release.yml:126,350`) only checks shape (`Scripts/verify-signature.sh`) | Nothing to rebrand |
| URL scheme | `project.yml:22,26` (`tinycast`, `tinycast-dev`) → `Info.plist:23–33`; `Info.plist:29` URL name "Raycast and Tinycast URL Scheme"; `ExtensionDeepLink.swift:38` hard-codes `"tinycast","tinycast-dev"` as own schemes | Change the 2 `project.yml` values; 1-line patch in `ExtensionDeepLink.swift:38` |
| Document type | `Info.plist:45–57` UTType `com.tinycast.backup`, extension `.tinycast`, "Tinycast Backup"; `BackupActions.swift:6` | Rename, or keep for import compatibility (it is user-visible as a file type) |
| Display name / copyright | `CFBundleName` = `$(PRODUCT_NAME)` (`Info.plist:13`), driven by target name `Tinycast` (`project.yml:39`) / `Tinycast Dev` (`project.yml:99`); `Info.plist:80–81` `NSHumanReadableCopyright` "Tinycast"; usage strings `Info.plist:69–75` | Set `PRODUCT_NAME` and the copyright string. Menu-bar strings already use `Bundle.main.appDisplayName` (`TinycastApp.swift:14`, `MenuBarItem.swift:17–33`) |
| Hard-coded "Tinycast" in UI | 91 distinct Swift literals in 73 files (e.g. `CommandID.swift` "Tinycast Settings", "About Tinycast", "Quit Tinycast", "Support Tinycast"); 841 occurrences in `Localizable.xcstrings` | The largest rebrand cost. Each rename is a patch hunk on hot files. Recommendation: rename only the high-visibility strings (CommandID names, About, Onboarding), or accept "Tinycast" in secondary copy |
| About / credits | `Windows/About/AboutView.swift:148–163`: tinycast.dev, github.com/abue-ammar/tinycast, Discord `discord.gg/v2Eeb4QQy3`, X `@abue_ammar`, `mailto:iabueammar@gmail.com` | Replace the links. Keep upstream credit wording if desired (AGPL, see the licensing row) |
| Support / donation | `Features/Support/UI/SupportCoordinator.swift:8` (`tinycast.dev/support`); `SupportWindowView.swift:72` "Secure checkout on Polar."; `MenuBarItem.swift:28`; `.github/FUNDING.yml:13` | Disable (section 3, Support) and delete `FUNDING.yml` |
| Release links in UI | `Palette/RootPaletteView.swift:218` (`github.com/abue-ammar/tinycast/releases`) | 1-line patch or leave |
| Telemetry / analytics | None. No analytics, Sentry or PostHog SDK; zero third-party deps. Outbound traffic: GitHub releases (updater), currency rates (`CurrencyRateStore`), Raycast store API (`ExtensionStoreResponse.swift:19`), GitHub raw (extension install), user-chosen AI/MCP endpoints | Nothing to strip |
| Logging / queue labels | `Logger(subsystem: "com.tinycast"…)` in `DeepLinkCoordinator.swift:16`, `ClipboardTextIndexer.swift:16`, `DictationAudioDucker.swift:18`, `ExtensionMenuBarManager.swift:421`; `Signposts.swift:6`; ~12 `DispatchQueue` labels; lock files `HyperKeyManager.swift:28`, `DictationKeyManager.swift:18` (`/tmp/com.tinycast.*.lock`, so instance ownership **collides with an installed Tinycast**); pasteboard type `ClipboardManager.swift:6` `com.tinycast.internal` | Invisible except the two lock files and the pasteboard type. Patch those 3 lines if Tinycast and Notchcast may run side by side |
| CI secrets / workflows | `release.yml:78–79,293–294` `SIGNING_P12_BASE64/PASSWORD`; `:184,380` `HOMEBREW_TAP_TOKEN` → `abue-ammar/homebrew-tinycast` (`:194`); `:223` `DISCORD_WEBHOOK_URL`; `:61–62` channel table (`Tinycast`, `com.tinycast.app[.beta]`, casks `tinycast`/`tinycast@beta`); `website.yml:53–55` `CLOUDFLARE_*`, `POLAR_ACCESS_TOKEN`; `gitlab-mirror.yml:26–27` (pushes to `gitlab.com/abue-ammar/tinycast`) | Delete or disable all workflows in the fork (they are upstream-only; a stray run fails for lack of secrets) |
| Release scripts | `Scripts/release-notes.sh:8,13–15,55,58` (repo, display name, bundle id, cask, brew tap text; `<!-- tinycast:install -->` marker `:18`); `Scripts/build-dmg.sh:7`; `Scripts/upload-website-media.sh:2,31` (`cdn.tinycast.dev`); `Scripts/benchmark-dictation.sh:10` (cache path) | Not needed for a local fork build. Leave untouched |
| Website | `website/` (Next.js + Cloudflare worker); `website/wrangler.jsonc:3,31` (`tinycast-website`, route `tinycast.dev`); `website/content/docs/**` | Exclude from the fork's build. Do not deploy |
| Issue / PR templates | `.github/ISSUE_TEMPLATE/bug_report.yml:9,64`; `.github/PULL_REQUEST_TEMPLATE.md`; `CONTRIBUTING.md`; `SECURITY.md` | Delete or ignore in the fork |
| Licensing | `LICENSE` (AGPL-3.0, "Copyright (C) 2026 Abue Ammar"); `NOTICE.md` (bundled as a resource, `project.yml:55–56`; third-party MIT/Apache notices incl. Rooms, LobeHub, opencode) | **Must keep** both. AGPL requires preserving notices and offering source for distributed builds. Add our own copyright line; do not remove upstream's |

### Minimal identity patch set (recommended)

- `project.yml`: 3 bundle-id values, 2 URL schemes, signing identity, target `PRODUCT_NAME`.
- `Info.plist`: copyright, URL name, UTType.
- `AppIndex.swift:819`.
- `ExtensionDeepLink.swift:38`.
- `AboutView.swift:148–163`.
- `SupportCoordinator.swift:8` (or hide Support).
- `MenuBarItem.swift:27–28`.
- The two lock-file paths.
- Delete `.github/workflows/*` and `FUNDING.yml`.

All other upstream identity is either inert under a new bundle id or confined to `website/` and release tooling the fork never runs.

Fork PRs never commit generated files or add runner registrations. Use the discovery convention in `notchcast/README.md`; CI regenerates the project before builds and commits generated outputs on main. Local Xcode users must regenerate before opening or building the project.

## Snapshot shipping

Main snapshots start on pushes to main, with a twenty-minute cron backstop and manual dispatch. One workflow-level concurrency lock covers planning through publication without cancelling in-flight runs. Sync's deploy-key push and land.sh's authenticated push trigger workflows; Generated's GITHUB_TOKEN push does not, so the backstop covers it. Automatic runs wait out the 50-minute gate on Ubuntu, then refresh main and releases before planning a pinned macOS build; unchanged main skips. Manual dispatch decides without waiting and fails with an error naming main and the gate's UTC opening time when gated, or main when unchanged. GitHub scheduling and runner availability can delay the intended build start within about 15 minutes of the gate opening. Sync's test action (runner exclusions, retries and pristine upstream comparison) and lint must pass; Leaks is independent. Failed attempts do not block retries. Signed arm64 zip/dmg artifacts use the same build and signing steps as sync. Snapshot annotated tags use the repository identity and identify the exact tested main commit.

The tag format is `<upstream-mirror-tag>.snapshot.<UTC YYYYMMDDHHMMSS>`. `update.sh` selects only tags ending in `.snapshot.<14 digits>` and orders them by timestamp alone, regardless of the upstream version. It checks up to 1000 releases so newer mirrors do not hide snapshots within that window. Run `bash notchcast/update-install-test.sh` for snapshot selection and ordering checks. Run `python3 notchcast/snapshot-test.py` for planning and skip checks. See [Snapshot releases](../README.md#snapshot-releases) for cadence, limitations and installation commands. `install-launchd.sh update --auto-install` enables `update.sh --install` every 30 minutes without changing the in-app preference; omit the option to restore default behavior.
