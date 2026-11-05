# Hidden features

Code stays compiled so upstream harnesses and future rebases retain their sources.

| State | Item | Tab slug | Command IDs | Forced off | Hooks |
| --- | --- | --- | --- | --- | --- |
| Hidden | Extensions | extensions | none | extensionsEnabled | AppSettings, AppCore startup, extension coordinator, launcher and hotkeys |
| Hidden | Fallbacks | fallbacks | none | FallbackStore.isEnabled | NotchcastHidden, sidebar, slug, search, FallbackStore |
| Hidden | Apple Shortcuts | apple-shortcuts | none | appleShortcutsEnabled | AppSettings, sidebar, slug, search; existing scanner and runner gates |
| Hidden | Support | none | command:support | supportRemindersEnabled, supportEnabled | catalog, hotkeys, launcher dispatch, SupportCoordinator, reminder startup; menu and About affordances |
| Hidden | About tab | about | none | none | sidebar, slug, search; page retained |

Not hidden on purpose: Backup and Raycast import (awaiting Damian), fork settingsBackup,
and About page (AGPL, menu bar). The menu bar and app menu call showAbout(), which selects
.about directly; SettingsDetailView renders AboutView independently of sidebar membership.
AboutView's footer carries the AGPL attribution; its GitHub link reaches the upstream
repository's LICENSE and NOTICE.md (the third-party licence list). No dedicated licence-list
view exists in the app. These files remain unchanged.

NotchcastHidden owns the hidden tab and command sets. On rebase retain the filtering hooks
and forced-off getters, even if upstream adds stored defaults or backup restore paths.

- Extensions: `AppSettings.extensionsEnabled` always reads false and ignores writes,
  including persisted consent and backup restore. `SettingsTab` omits its sidebar row
  and rejects its settings slug; `SettingsSearchCatalog` omits its search entries.
  Upstream's `ExtensionManager` publishes no launcher entries while off; `HotKeyManager` exposes no bound extension
  commands, and `LauncherCoordinator`, `AppActionsMenu`, `RootPaletteView` and
  `LauncherScreen+AliasSpace` gate extension actions/accessories. `ExtensionCoordinator`
  rejects store-install links as well as its existing command-link gate. `AppCore`
  gates manager startup. No runtime dependency from an active fork feature exists.
- Agent Answers: hidden by #209 because no reply transport exists; #336 prevents
  backups from enabling unwired `NotchcastFeature` switches. That fork preference
  guard does not cover upstream `AppSettings`; Extensions uses the separate read gate
  above and does not duplicate #336's backup filter.
