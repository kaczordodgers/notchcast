# Hidden features

The one list of what Notchcast hides and how. Code stays compiled so upstream harnesses and future rebases retain their sources. `Tests/notchcast-hidden-features-test.swift` reads the table below and fails if a hidden item returns to the Settings sidebar, Settings search or the launcher.

## Upstream features

| State | Item | Tab slug | Command IDs | Forced off | Hooks |
| --- | --- | --- | --- | --- | --- |
| Hidden | Extensions | extensions | none | extensionsEnabled | AppSettings, AppCore startup, extension coordinator, launcher and hotkeys |
| Hidden | Fallbacks | fallbacks | none | FallbackStore.isEnabled | NotchcastHidden, sidebar, slug, search, FallbackStore |
| Hidden | Apple Shortcuts | apple-shortcuts | none | appleShortcutsEnabled | AppSettings, sidebar, slug, search; existing scanner and runner gates |
| Hidden | Support | none | command:support | supportRemindersEnabled, supportEnabled | catalog, hotkeys, launcher dispatch, SupportCoordinator, reminder startup; menu and About affordances |
| Hidden | About tab | about | none | none | sidebar, slug, search; page retained |

| Hidden | Backup | backup | none | none | sidebar, slug, search; Notchcast Backups retains sync, export and import |
| Hidden | Raycast import | none | command:import-from-raycast | none | catalog, hotkeys, launcher dispatch and deeplinks |

Not hidden on purpose: the fork `settingsBackup` feature, and the About page (AGPL notices). The menu bar and app menu call `showAbout()`, which selects `.about` directly; `SettingsDetailView` renders `AboutView` independently of sidebar membership. AboutView's footer carries the AGPL attribution; its GitHub link reaches the upstream repository's `LICENSE` and `NOTICE.md`.

`NotchcastHidden` owns the hidden command set and flags; `NotchcastHidden+Tabs` owns the hidden tab set (it needs `SettingsTab`, so harnesses get it only with `SettingsTab.swift`). On rebase retain the filtering hooks and forced-off getters, even if upstream adds stored defaults or backup restore paths.

- Extensions: `AppSettings.extensionsEnabled` always reads false and ignores writes, including persisted consent and backup restore. `SettingsTab` omits its sidebar row and rejects its settings slug; `SettingsSearchCatalog` omits its search entries. Upstream's `ExtensionManager` publishes no launcher entries while off; `HotKeyManager` exposes no bound extension commands, and `LauncherCoordinator`, `AppActionsMenu`, `RootPaletteView` and `LauncherScreen+AliasSpace` gate extension actions and accessories. `ExtensionCoordinator` rejects store-install links as well as its existing command-link gate. `AppCore` gates manager startup. No active fork feature depends on the extension runtime.
- The `AppSettings` read gates are separate from #336's backup filter below, which covers only fork `NotchcastFeature` switches.

## Fork features

Unwired fork features start off and are absent from Settings, search and the launcher; see `NotchcastFeature.unwired` in `Tinycast/Features/Notchcast/Core/NotchcastFeature.swift`. Settings backup restore writes their switches as false, so importing a backup cannot enable them (#336). Direct preference changes remain available to harnesses testing the kept code.

Agent Answers (`agentAnswer`) was already hidden by #209 because no reply transport exists; its code stays in place.
