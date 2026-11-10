# Tinycast architecture map (for the Notchcast patch queue)

Source: read-only clone of upstream `abue-ammar/tinycast` at HEAD `3be769dc` ("Add move-to-edge window commands (#1781)"). All `path:line` citations are relative to that clone and were read at that commit. Doc claims (AGENTS.md, docs/) were checked against code; where they disagree, it says so.

## 1. Shape at a glance

- 1327 tracked files: 912 under `Tinycast/`, 137 `Tests/`, 44 `Scripts/`, 44 `docs/`, 160 `website/` (from `git ls-files | cut -d/ -f1 | uniq -c`).
- Native macOS accessory app (`LSUIElement`), SwiftUI + AppKit, macOS 26.0 deployment target, Swift 6, strict concurrency complete (`project.yml:5`, `project.yml:14`, `project.yml:19`).
- One composition root: `AppCore.shared` (`Tinycast/App/AppCore.swift:6-7`). Everything long-lived hangs off it.
- No notch surface exists upstream: `grep -rli notch Tinycast` returns nothing. Notchcast's notch UI is entirely fork-added; the closest upstream analogues are the palette panel and the floating non-activating panels (Notes, Camera).

## 2. Modules and layers

### Folder → responsibility (Swift files / lines, `find … -name '*.swift' | xargs cat | wc -l`)

| Folder | Files | Lines | Responsibility |
| --- | ---: | ---: | --- |
| `Tinycast/App/` | 4 | 1214 | `@main`, `AppDelegate`, `AppCore` (1018 lines), menu-bar item |
| `Tinycast/Palette/` | 22 | 4277 | palette shell: `PalettePanel`, `PaletteWindowController`, `RootPaletteView` (1638 lines), `PaletteMode`, `PaletteScreen` protocol, `PaletteCoordinator` |
| `Tinycast/Windows/` | 16 | 1323 | non-palette AppKit surfaces: `AppWindowController`, `Dialog/`, `HUD/`, `About/` |
| `Tinycast/DesignSystem/` | 36 | 4467 | `Theme` tokens, shared views, `Scrolling/` (two files off-limits per AGENTS.md) |
| `Tinycast/Platform/` | 41 | 2521 | system shims: `AppPaths`, `AppURLScheme`, `Permissions`, `LaunchAtLogin`, `HealthTicker`, `NotificationToken`, `Images/IconCache` |
| `Tinycast/Migrations/` | 1 | 20 | one-shot repairs, each deleted after one stable release |
| `Tinycast/Features/` | 728 | 114563 | one folder per feature (below) |

Feature folders (files / lines): AI 99/20631 · Extensions 78/14549 · WindowManagement 62/8977 · Calculator 33/6315 · Launcher 45/6149 · Notes 36/5639 · Settings 32/4735 · HotKeys 33/4377 · Clipboard 25/4114 · Snippets 16/3591 · Emoji 10/3524 · FileSearch 24/3418 · Backup 19/2994 · Dictation 26/2912 · MCP 22/2874 · Calendar 27/2681 · CustomCommands 15/2667 · Quicklinks 14/2457 · QuickActions 19/2292 · Uninstall 11/1417 · Updates 16/1414 · TextInjection 4/1282 · SystemActions 8/1112 · MenuSearch 11/856 · DeepLinks 7/793 · Dictionary 7/644 · WindowSwitcher 10/560 · Onboarding 4/537 · Camera 6/494 · Support 4/261 · AppleShortcuts 4/253.

### Layering inside a feature

`docs/architecture.md:6-61` defines four layers, mapped to sub-folders (`docs/architecture.md:63-64`):

- `Model/` — pure, Foundation-only (SQLite3/CoreGraphics allowed); environment facts injected. Enforced because `Tests/*.swift` harnesses compile the shipped sources with plain `swiftc` (`Scripts/run-tests.sh:26`). Rule: no `import AppKit|SwiftUI` under `Features/*/Model/` (`AGENTS.md:69-70`).
- `Service/` — effects: stores, monitors, runners, AX/CGEventTap/URLSession/FileManager.
- `UI/` — screens, views and the feature's `…Coordinator` (the only place actions live).
- `Settings/` — the feature's own Settings pane(s).

Small features stay flat (e.g. `Features/Onboarding/`). Out-of-process helpers are separate XcodeGen targets excluded from the app target: `ClipboardTextHelper`, `FileIndexHelper`, `DictationHelper` (`project.yml:45-50`, `project.yml:101-157`), embedded into `Contents/Helpers` (`project.yml:57-83`).

## 3. App lifecycle and entry points

1. `TinycastLaunch.main()` pins the UI language then runs the SwiftUI app (`Tinycast/App/TinycastApp.swift:3-8`).
2. `TinycastApp` declares only two `MenuBarExtra` scenes (app item + calendar item) and the main-menu `.commands` (`Tinycast/App/TinycastApp.swift:17-30`, `Tinycast/App/TinycastApp.swift:70-88`). Everything else is imperative AppKit.
3. `AppDelegate.applicationWillFinishLaunching` forces overlay scrollers (`Tinycast/App/AppDelegate.swift:7-9`); `applicationDidFinishLaunching` calls `AppCore.shared.start(launchedByUser:)` and nothing else (`Tinycast/App/AppDelegate.swift:11-13`). `isUserLaunch` distinguishes a plain open from login-item/URL launch via the Apple Event (`Tinycast/App/AppDelegate.swift:65-71`).
4. `AppCore.init` builds the eager stores (settings, ranking, chat history, app index, clipboard, snippets, notes) (`Tinycast/App/AppCore.swift:261-285`).
5. `AppCore.start` is the whole boot sequence in one function (`Tinycast/App/AppCore.swift:287-473`): migrations first (`:291`), `.accessory` activation policy (`:292`), appearance/motion (`:294-296`), per-feature `applyEnabled()` / `apply…Presence()` (`:301-356`), async loads (`:357-359`), hotkey callback wiring (`:372-409`), `hotKeys.start(…)` (`:432-438`), Hyper/Dictation keys (`:440-443`), snippets (`:445-457`), `observeFeatureSwitches()` (`:459`), onboarding or palette (`:462-467`), then drains URLs that arrived before boot (`:472`, `:475-479`).
6. URLs: `AppDelegate.application(_:open:)` → `AppCore.handleOpenURL` (`Tinycast/App/AppDelegate.swift:15-19`), which queues until `start` finishes, then routes to `DeepLinkCoordinator` or the Raycast-extension router (`Tinycast/App/AppCore.swift:491-511`).
7. Reopen (Dock/Finder re-launch): focuses the first existing window, else shows the palette (`Tinycast/App/AppCore.swift:481-489`).
8. Termination: `applicationShouldTerminate` returns `.terminateLater`, awaits dictation stop and notes flush (`Tinycast/App/AppDelegate.swift:26-43`); `applicationWillTerminate` → `AppCore.prepareForTermination` (HID remaps first, then every service's stop) (`Tinycast/App/AppDelegate.swift:21-24`, `Tinycast/App/AppCore.swift:600-619`).

Windows (from `docs/architecture.md:129-183`, verified for palette): the palette is a borderless `NSPanel` hosting `RootPaletteView` through `paletteEnvironment(core)` (`Tinycast/Palette/PaletteWindowController.swift:373`); Settings/Onboarding/AI Chat/Support use `Windows/AppWindowController.swift`; dialogs only via `DialogController`, never `NSAlert` (`AGENTS.md:85-86`).

## 4. Main services / singletons

- Exactly one singleton: `AppCore.shared` (`Tinycast/App/AppCore.swift:7`). The rule "new long-lived state goes on `AppCore`, wired in `start()` — never a competing singleton" is a non-negotiable (`AGENTS.md:67-68`). `NotchcastHost.current` (`Tinycast/Features/Notchcast/Core/NotchcastHost.swift`) holds no state, only closures `NotchcastCore.start` sets to `AppCore`, so fork modules and harnesses need no `AppCore`; only the command files, which still call `AppCore.shared`, keep their harnesses' `AppCore` stubs. Harnesses compile the kernel from `Tests/Kit/core.kit` and the seam from `host.kit`, and assert on messages by setting the `NotchcastHost.current` closures.
- Eager stores/services as `let` properties: `LauncherRankingStore`, `AppIndex`, `CustomCommandStore`, `QuicklinkStore`, window layout/room stores, `ClipboardStore`, `ClipboardManager`, `SnippetsStore`, `SnippetKeywordListener`, `TextInjector`, `HotKeyManager`, `WindowMover`, `AppSettings`… (`Tinycast/App/AppCore.swift:9-37`).
- Coordinators are all `@ObservationIgnored private(set) lazy var` so reading them does not register Observation dependencies (`Tinycast/App/AppCore.swift:89-242`; rationale `docs/architecture.md:192-194`). Examples: `paletteCoordinator` (`:119`), `settingsCoordinator` (`:124`), `notesCoordinator` (`:167`), `launcherCoordinator` (`:177`), `deepLinkCoordinator` (`:239`).
- `AppCore` forwards UI primitives so dialogs/HUD stay single-owned: `confirm`, `choose`, `reportFailure`, `showMessage`, `showProgress` (`Tinycast/App/AppCore.swift:956-1003`).
- Views reach coordinators via `@Environment(AppCore.self)` as a locator; the palette injects ~25 stores (`Tinycast/Palette/PaletteEnvironment.swift:14-39`). A missing injection compiles and traps at runtime (`docs/architecture.md:197-199`).

## 5. Data and settings storage

### UserDefaults

- `AppSettings` (`@MainActor @Observable`, `Tinycast/Features/Settings/AppSettings.swift:108-112`) is the one preferences object; each property writes through in `didSet` (e.g. `Tinycast/Features/Settings/AppSettings.swift:115-117`) and is read in `init()` (`Tinycast/Features/Settings/AppSettings.swift:684-699`). Keys are the `AppSettingsKey` enum, raw values spelled out so a rename never renames a persisted key (`Tinycast/Features/Settings/AppSettingsKey.swift:3-6`). Feature switches follow `<feature>Enabled` / `<feature>ShowInLauncher` (e.g. `Tinycast/Features/Settings/AppSettingsKey.swift:36-60`). Only `clipboardEnabled` defaults on (`Tinycast/Features/Settings/AppSettings.swift:685-688`).
- Feature-owned keys outside `AppSettingsKey`: `launcherAliases` (`Tinycast/Features/Launcher/Service/AliasStore.swift:8`), `hiddenLauncherItems` / `hiddenLauncherKinds` (`Tinycast/Features/Launcher/Service/VisibilityStore.swift:8-9`), `favoriteApps` (`Tinycast/Features/Launcher/Service/FavoritesStore.swift:7`), `fallbackOrder` / `disabledFallbacks` (`Tinycast/Features/Launcher/Service/FallbackStore.swift:7-8`), `customCommands` (`Tinycast/Features/CustomCommands/Model/CustomCommand.swift:151`), `hiddenMeetingCalendars` (`Tinycast/Features/Calendar/Service/CalendarStore.swift:26`), `boundAppBundleIDs` / `boundPaneBundleIDs` (`Tinycast/Features/HotKeys/Service/HotKeyManager.swift:82-83`), `notesActiveFileName` (`Tinycast/App/AppCore.swift:278`), `notesFormattingBarExpanded` (`Tinycast/App/AppCore.swift:166`).
- Hotkey bindings: one key per action, `hotkey.<…>` (`Tinycast/Features/HotKeys/Model/HotKeyAction.swift:24-45`).
- Channel isolation: Debug is `com.tinycast.app.dev` / scheme `tinycast-dev`, so it never shares prefs with an installed copy (`project.yml:22-27`); anything persisted must key off `Bundle.main.bundleIdentifier` (`AGENTS.md:135-137`).

### Files

- Roots: `AppPaths.applicationSupport()` / `caches()` keyed by bundle ID (`Tinycast/Platform/AppPaths.swift:5-15`); Notes/Snippets folders are user-relocatable `contentFolder` (`Tinycast/Platform/AppPaths.swift:28-34`).
- SQLite: `clipboard.sqlite3` (`Tinycast/Features/Clipboard/Model/ClipboardStore.swift:292`), `quicklinks.sqlite3` (`Tinycast/Features/Quicklinks/Model/QuicklinkStore.swift:40`), `ai-chats.sqlite3` (`Tinycast/Features/AI/Service/ChatHistoryStore.swift:101`).
- JSON: `launcher-ranking.json` (`Tinycast/Features/Launcher/Model/LauncherRankingStore.swift:164`), `quick-actions.json` (`Tinycast/Features/QuickActions/Model/CustomQuickActionStore.swift:15`), `room-parking.json` (`Tinycast/App/AppCore.swift:17-18`), `currency-rates.json` in Caches (`Tinycast/Features/Calculator/Service/CurrencyRateStore.swift:27`); also calculator history, emoji pins/frequency, update-check, support-reminder (grep `appendingPathComponent("…json")`).
- Notes and Snippets are plain Markdown/text files in their folders (`Tinycast/App/AppCore.swift:889-896`).

### settings.json (opt-in mirror)

- Path `~/.config/tinycast/settings.json`; non-stable bundle IDs get `tinycast-<suffix>` (`Tinycast/Platform/AppPaths.swift:18-25`, `Tinycast/Platform/AppPaths.swift:56-61`). A Notchcast bundle ID that does not start with `com.tinycast.app` gets a folder named after the raw bundle ID (`:59`).
- Keys: `SettingsFileKey`, dotted `section.name` raw values in file order (`Tinycast/Features/Settings/Model/SettingsFileKey.swift:3-6`). Binding: exhaustive switch in `SettingsFileSchema.binding(for:)` — a new key fails the build until bound (`Tinycast/Features/Settings/SettingsFileSchema.swift:3-30`). Format: sectioned JSON, rendered in key order, unknown keys reported as issues, never fatal (`Tinycast/Features/Settings/Model/SettingsFileFormat.swift:10-29`, `:43`).
- Lifecycle: `AppCore.startSettingsFile(importing:)` builds the repository after the first app scan (`Tinycast/App/AppCore.swift:413-422`, `Tinycast/App/AppCore.swift:906-925`); file changes are watched with `DispatchSource` file-system sources (`Tinycast/Features/Settings/Service/SettingsFileMonitor.swift:10-11`).
- Capability flags never travel in a backup: `snippetsEnabled`, OCR, etc. are excluded with a reason in `SettingsBackupCoverage` (`Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift:98-101`); `Tinycast/Features/Backup/Model/SettingsBackup.swift:60` repeats it.

### Migrations


## 6. How a feature registers

Canonical example: Notes. Every touchpoint is a closed `enum`/`switch`, so the compiler lists what a new case must fill in.

| Surface | Registration point | Cite |
| --- | --- | --- |
| Built-in launcher command | add a case to `CommandID` (raw `command:<slug>`) + its `name`/icon switches | `Tinycast/Features/Launcher/Model/CommandID.swift:3-49`, `:150-176` |
| Command shown in launcher | automatic: `CommandCatalog.all` maps every non-query-driven `CommandID` | `Tinycast/Features/Launcher/Model/CommandCatalog.swift:5-9` |
| Command action | `LauncherCoordinator.runCommand(_:)` exhaustive switch | `Tinycast/Features/Launcher/UI/LauncherCoordinator.swift:166-236` |
| Which Settings pane lists it | `SettingsTab.ownedCommands` | `Tinycast/Features/Launcher/Model/CommandCatalog.swift:51-71` |
| Entry category | `AppEntry.Kind` (+ `KindDescriptor`) — the only source of "what an entry is" | `Tinycast/Features/Launcher/Service/AppIndex.swift:3-26`; `AGENTS.md:104-106` |
| Dynamic entries | `AppIndex.set…` slices (`setQuicklinks`, `setExtensionCommands`, …) | `Tinycast/Features/Launcher/Service/AppIndex.swift:444-498` |
| Feature on/off | coordinator `applyEnabled()` calls `appIndex.setCommandsVisible(…)` / `setCommandsListed(…)` | `Tinycast/Features/Notes/UI/NotesCoordinator.swift:99-103`; `Tinycast/Features/Launcher/Service/AppIndex.swift:425-442` |
| React to settings change | `AppCore.observeFeatureSwitches()` → `track({ _ = $0.x }, reproject:)` | `Tinycast/App/AppCore.swift:674-796`, `track` at `:844-858` |
| Boot wiring | call `…Coordinator.applyEnabled()` in `AppCore.start` | `Tinycast/App/AppCore.swift:301-356` |
| Coordinator ownership | `lazy var …Coordinator` on `AppCore` | `Tinycast/App/AppCore.swift:89-242` |
| Settings pane | case in `SettingsTab` (+ slug/title/icon) → `SettingsSection.tabs` → `SettingsDetailView` switch | `Tinycast/Features/Settings/SettingsTab.swift:1-4`, `:14-40`, `:114-130`; `Tinycast/Features/Settings/SettingsDetailView.swift:10-32` |
| Settings search | `SettingsSearchCatalog` entries (`.init(pane:keywords:)`), checked by `Scripts/check-settings-search.js` | `Tinycast/Features/Settings/SettingsSearchCatalog.swift:385` |
| Preference | `AppSettingsKey` case + `AppSettings` property (didSet + init read) + `SettingsFileKey` + `SettingsFileSchema` binding + backup coverage | `Tinycast/Features/Settings/AppSettingsKey.swift:41`, `Tinycast/Features/Settings/AppSettings.swift:347`, `:779`, `Tinycast/Features/Settings/Model/SettingsFileKey.swift:75`, `Tinycast/Features/Settings/SettingsFileSchema.swift:97` |
| Hotkey | free for any `CommandID`: `HotKeyAction.command(id)` + `builtInActions` derive from the catalog | `Tinycast/Features/HotKeys/Model/HotKeyAction.swift:7-8`, `:47-48`; `Tinycast/Features/Launcher/Model/CommandID.swift:226-228` |
| Hotkey dispatch | `HotKeyManager` → `onRunCommand` closure → `launcherCoordinator.runCommand` | `Tinycast/Features/HotKeys/Service/HotKeyManager.swift:428-430`; `Tinycast/App/AppCore.swift:378` |
| Hotkey gate | `AppCore.allowsHotKeyAction` (visibility + `isCommandEnabled`) | `Tinycast/App/AppCore.swift:513-519` |
| Non-command hotkey kind | new `HotKeyAction` case + `defaultsKey` + `onRun…` closure + `hotKeyDisplayName` | `Tinycast/Features/HotKeys/Model/HotKeyAction.swift:3-45`; `Tinycast/App/AppCore.swift:522-550` |
| Carbon registration | `HotKeyCenter` (`RegisterEventHotKey`, `InstallEventHandler`) | `Tinycast/Features/HotKeys/Service/HotKeyCenter.swift:76`, `:108` |
| Deeplink | automatic for any entry: `tinycast://<kind>/<id>` parses to `.entry(HotKeyAction, input)`; `settings/<slug>`, `note/`, `chat/`, `window-size` are explicit | `Tinycast/Features/DeepLinks/Model/DeepLink.swift:4-12`, `:60-78`; routing `Tinycast/Features/DeepLinks/UI/DeepLinkCoordinator.swift:44-60` |
| URL schemes | `raycast` + `$(TINYCAST_URL_SCHEME)` in Info.plist | `Tinycast/Info.plist:25-33` |
| Palette screen | `PaletteMode` case → `RootPaletteView.screen` switch returning a `PaletteScreen` | `Tinycast/Palette/PaletteMode.swift:3-28`; `Tinycast/Palette/RootPaletteView.swift:52-133`; protocol `Tinycast/Palette/PaletteScreen.swift:76-106` |
| Open a palette mode | `PaletteCoordinator.togglePalette(mode:)` / `showPalette(mode:)` | `Tinycast/Palette/PaletteCoordinator.swift:66`, `:84` |
| Menu bar (app item) | static SwiftUI menu in `MenuBarMenu`; a feature row is gated by reading its setting | `Tinycast/App/MenuBarItem.swift:13-34` |
| Menu bar (own item) | a feature-owned `NSStatusItem` controller (Notes, extensions) | `Tinycast/Features/Notes/UI/NotesMenuBarController.swift:6`; `Tinycast/Features/Extensions/UI/ExtensionMenuBarController.swift:56` |
| Main menu | `TinycastApp.menuBarCommands` | `Tinycast/App/TinycastApp.swift:70-88` |
| Compact bar | `CommandID.compactBarOptions` | `Tinycast/Features/Launcher/Model/CommandID.swift:55-58` |

## 7. Concurrency model

- Swift 6 mode, `SWIFT_STRICT_CONCURRENCY: complete` (`project.yml:14`, `:19`). No `defaultIsolation`/`SWIFT_DEFAULT_ACTOR_ISOLATION` setting: `@MainActor` is written explicitly (468 occurrences in `Tinycast/`), e.g. `AppCore` (`Tinycast/App/AppCore.swift:4-6`) and `AppSettings` (`Tinycast/Features/Settings/AppSettings.swift:108-110`).
- No custom `actor` type exists at this HEAD (grep for actor declarations finds none); docs' "exactly one actor" (`docs/architecture.md:211`) effectively means the main actor. Off-main work uses `nonisolated static` functions + `Task.detached` (78 `Task.detached` sites) and one `@concurrent` function.
- Observation everywhere: 87 `@Observable` sites, no `ObservableObject`/`@Published`. Outside views, `AppCore.track` re-arms `withObservationTracking` from a `Task` because `onChange` is a one-shot willSet (`Tinycast/App/AppCore.swift:843-858`; `docs/architecture.md:201-204`).
- Combine is marginal: imported in 4 view files only, for `Timer.publish` refreshes (e.g. `Tinycast/Features/Settings/Panes/PermissionsSettingsView.swift:11`, `:158`).
- Callback-closure wiring instead of publishers: services expose `on…` closures that `AppCore.start` binds with `[weak self]` (`Tinycast/App/AppCore.swift:372-412`).
- `MainActor.assumeIsolated` bridges AppKit/KVO callbacks (35 sites), e.g. `Tinycast/App/AppCore.swift:831-833`.
- Shutdown is ordered and synchronous (`Tinycast/App/AppCore.swift:600-619`), with an async veto-free flush beforehand (`Tinycast/App/AppDelegate.swift:35-41`).

## 8. Third-party dependencies

- **None in the app.** No SwiftPM: zero `XCRemoteSwiftPackageReference` in `Tinycast.xcodeproj/project.pbxproj`, no `Package.resolved` anywhere, and AGENTS.md says "Zero third-party dependencies" / "No SwiftPM, and never `Bundle.module`" (`AGENTS.md:6-7`, `AGENTS.md:138-139`). `project.yml` has only app/helper targets (`project.yml:38-157`).
- Apple frameworks of note: Carbon.HIToolbox (24 files, global hotkeys/TIS — a deliberate exception, `AGENTS.md:33-35`), JavaScriptCore (Raycast extension runtime), SQLite3, EventKit, CoreML/Accelerate (dictation), FoundationModels, Vision/PDFKit (helper only), ServiceManagement (`SMAppService` login item), IOKit.hid (Hyper key).
- Build-time JS only: `Scripts/raycast-runtime/package.json` devDependencies `@raycast/api`, `esbuild`, `react`, `react-reconciler` (pnpm lock) build `Resources/RaycastRuntime.generated.js`, which is committed so the app build never needs Node (`AGENTS.md:107-111`).
- Runtime downloads (not bundled): dictation models from Hugging Face (Parakeet, Qwen3-ASR) per `NOTICE.md:5-19`.
- Tooling: XcodeGen owns the project (`AGENTS.md:138-139`); swift-format, SwiftLint (`.swift-format`, `.swiftlint.yml`).

## 9. Where a fork patch touches least

Ranked narrowest first. "Hunks" = upstream files a patch must edit, which is what conflicts on rebase.

### Hiding an upstream feature

1. **Default a feature switch off — 1 hunk.** Every feature except Clipboard already defaults off (`Tinycast/Features/Settings/AppSettings.swift:685-688`, `:779` reads `bool`, default false). If Notchcast only needs a feature off by default, no patch is needed; for Clipboard edit `:685-688`.
2. **Force-hide at runtime without touching feature code — 1 hunk in `AppCore.start`.** After the per-feature `applyEnabled()` calls, call `appIndex.setCommandsVisible([...], false)` (`Tinycast/Features/Launcher/Service/AppIndex.swift:429-434`). Because `allowsHotKeyAction` consults `isCommandEnabled` (`Tinycast/App/AppCore.swift:513-519`), shortcuts and deeplinks to those commands go too. Caveat: the feature's own `applyEnabled()` re-shows them when its setting flips (`Tinycast/Features/Notes/UI/NotesCoordinator.swift:102`), so the hide must also be re-applied from `track` or done by pinning the setting.
3. **Hide a Settings pane — 1 hunk.** Remove the tab from `SettingsSection.tabs` (`Tinycast/Features/Settings/SettingsTab.swift:114-130`). The enum case, deeplink slug and detail-view switch stay intact, so nothing else breaks. Also drop its `SettingsSearchCatalog` entries or search will still offer it (`Tinycast/Features/Settings/SettingsSearchCatalog.swift:385`).
4. **Hide a whole launcher category — no code.** `VisibilityStore.setKindEnabled(false, for:)` persists to `hiddenLauncherKinds` (`Tinycast/Features/Launcher/Service/VisibilityStore.swift:70-74`); seeding that default is a one-line `register(defaults:)` next to `Tinycast/App/AppCore.swift:290`.
5. **Hide a menu-bar row — 1 hunk** in `MenuBarMenu` (`Tinycast/App/MenuBarItem.swift:13-34`).

Avoid deleting `CommandID` cases or `SettingsTab` cases: both feed exhaustive switches in many files (`LauncherCoordinator`, `SettingsDetailView`, `SettingsFileSchema`, `DeepLinkCoordinator`), so a deletion becomes a many-file patch that conflicts on every upstream rebase.

### Adding a feature

Minimum seam for a self-contained Notchcast feature (e.g. the notch surface):

- **New folder `Tinycast/Features/<Name>/`** with `Model/ Service/ UI/ Settings/` — zero conflicts, XcodeGen picks it up from `sources: - path: Tinycast` (`project.yml:42-43`) after `xcodegen generate` (PR CI regenerates the project; PRs never commit it).
- **String catalog conflicts.** During a conflicted merge, rebase or cherry-pick, run `python3 notchcast/xcstrings-union.py --git`: three-way reconciliation via the merge base, keeping main's text and order.
  Branch-only keys are inserted as text; deleted keys stay deleted, and value conflicts are reported for resolution before staging.
  `.github/workflows/pr.yml` checks catalog keys; `notchcast/xcstrings-allowed-keys.json` is the escape hatch for intentional key changes.
  Tests: `python3 notchcast/test-xcstrings.py`.
- **`AppCore` — 2 hunks:** one `lazy var <name>Coordinator` beside the others (`Tinycast/App/AppCore.swift:217-242` is the block), one `applyEnabled()` call in `start` (`:301-356`) plus, if it has a switch, one `track` in `observeFeatureSwitches` (`:674-796`). Optionally a teardown line in `prepareForTermination` (`:600-619`).
- **Preference — 4 hunks** if it must round-trip through settings.json: `AppSettingsKey`, `AppSettings` (property + init), `SettingsFileKey`, `SettingsFileSchema` (exhaustive, build fails otherwise; `Tinycast/Features/Settings/SettingsFileSchema.swift:3`), plus a `SettingsBackupCoverage` entry. Fork-local preference that need not sync: read/write `UserDefaults` from the feature's own store (as `AliasStore` does, `Tinycast/Features/Launcher/Service/AliasStore.swift:8-16`) — zero shared hunks.
- **Launcher command + hotkey + deeplink — 3 hunks:** a `CommandID` case (name/icon switches in the same file, `Tinycast/Features/Launcher/Model/CommandID.swift`), one `runCommand` case (`Tinycast/Features/Launcher/UI/LauncherCoordinator.swift:166`), and optionally `ownedCommands` (`Tinycast/Features/Launcher/Model/CommandCatalog.swift:51-71`). Hotkey and deeplink come for free (`Tinycast/Features/HotKeys/Model/HotKeyAction.swift:47-48`, `Tinycast/Features/DeepLinks/Model/DeepLink.swift:76`).
- **Settings pane — 3 hunks:** `SettingsTab` case (+ slug/title/icon in the same file), `SettingsSection.tabs`, `SettingsDetailView` switch.
- **A new window/surface:** follow `NotesWindowController`/`CameraPanel` (feature-owned AppKit panel), never a SwiftUI scene (`docs/architecture.md:145-155`) and never `NSAlert` (`AGENTS.md:85-86`).

Patch-queue hygiene implied by the code: keep fork code in fork-only files and limit shared-file edits to single-line insertions at list ends (enum cases, switch arms, `start` calls); those are the hunks that rebase cleanly.

## 10. Signals for the dependency-graph script

- **Imports** are uninformative (single module; 434 `import Foundation`, 275 `SwiftUI`, 183 `AppKit`). Use them only for the layer rule: any `import AppKit|SwiftUI|Cocoa` under `Features/*/Model/` is a violation (`AGENTS.md:148`).
- **Type references:** build a symbol table of top-level `struct|class|enum|protocol|extension` names per file, then map identifier references to defining files; aggregate to feature folder (`Features/<X>/`) for the graph edges.
- **Registries (closed enums/switches):** `CommandID`, `AppEntry.Kind`, `SettingsTab`, `SettingsSection.tabs`, `SettingsFileKey`, `AppSettingsKey`, `HotKeyAction`, `PaletteMode`, `DeepLink`, plus the switches in `LauncherCoordinator.runCommand`, `SettingsDetailView`, `SettingsFileSchema.binding`, `RootPaletteView.screen`, `AppCore.hotKeyDisplayName`. Emit "feature X registers in registry R" edges from `case` arms naming X's types.
- **Composition root:** `AppCore` `let`/`lazy var` properties (owner edges), `start()` call order (boot edges), `track(...)` closures (settings → coordinator edges), `hotKeys.on… =` assignments (hotkey → coordinator edges).
- **Environment injection:** `.environment(core.X)` in `PaletteEnvironment.swift` and `@Environment(T.self)` in views (view → store edges).
- **Coordinator access:** `core.<name>Coordinator` member chains (cross-feature edges; the main coupling signal).
- **Persistence keys:** string literals passed to `forKey:` and `appendingPathComponent("*.json|*.sqlite3")` (feature → storage edges).
- **Build graph:** `project.yml` target `sources` lists (helper targets compile specific feature files) and `Tests/*.swift` upstream source lists in `Scripts/run-tests.sh` and fork source headers (which shipped files each harness compiles).

## Ownership

Notchcast deliberately keeps its composition inside `Tinycast/Features/Notchcast/` to minimize upstream rebase conflicts: the sole Notchcast startup hook in `AppCore.start()` is `NotchcastCore.start(self)`. This is a fork-specific exception to upstream's rule that `AppCore` owns all long-lived state, not an instance ownership tree rooted in `AppCore`.

`NotchcastCore` retains the static feature modules, quit-protection store and event-tap hub, plus the monitor module and `NotchcastModuleController` created at startup. The controller retains its module entries and preferences. Existing process-lifetime singletons are `IslandController.shared` (panels, page coordinator, input state and observers), `IslandActivityCenter.shared` (activities, messages and dismissal task, with a weak presenter), and `NotchcastPreferences.shared` (observable preferences persisted in the bundle-specific `.notchcast` UserDefaults suite).

`NotchcastCore.start` is guarded against duplicate startup, configures island pages once, registers modules and runs the controller. `NotchcastModuleController` observes feature switches: every `requires` switch must be on, and a nonempty `requiresAny` group needs at least one switch on; transitions call each module's `start()` or `stop()` once. Disabling a feature stops its resources without releasing its process-lifetime instance. Island shutdown clears its activity presenter, closes panels and the open page, cancels hover work and removes observers and event monitors. Termination separately calls `NotchcastCore.stopForTermination()` from `AppDelegate` to stop and await battery and monitor fan work; there is no controller-wide termination stop.

Battery and fan termination drains share a three-second budget. Root helper timeout and cancellation abandon the child without sending a signal; its detached exit observer can finish later. Ownership journals remain available for repair on the next launch.

New features register a module in `NotchcastCore` with their switch requirements and own their resources through `start()`/`stop()`; add no new `AppCore` lines. Add no new singletons unless the module needs a tap-thread or AppKit-global handle; ordinary feature state belongs to the module.

See [command-hook.md](command-hook.md) for the fork's command integration seam.
