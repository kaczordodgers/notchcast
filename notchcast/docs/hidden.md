# Hidden features

Code stays compiled so upstream harnesses and future rebases retain their sources.

- Extensions: `AppSettings.extensionsEnabled` always reads false and ignores writes,
  including persisted consent and backup restore. `SettingsTab` omits its sidebar row
  and rejects its settings slug; `SettingsSearchCatalog` omits its search entries.
  `AppIndex` rejects extension entries, `HotKeyManager` exposes no bound extension
  commands, and `LauncherCoordinator`, `AppActionsMenu`, `RootPaletteView` and
  `LauncherScreen+AliasSpace` gate extension actions/accessories. `ExtensionCoordinator`
  rejects store-install links as well as its existing command-link gate. `AppCore`
  gates manager startup. No runtime dependency from an active fork feature exists.
- Agent Answers: hidden by #209 because no reply transport exists; #336 prevents
  backups from enabling unwired `NotchcastFeature` switches. That fork preference
  guard does not cover upstream `AppSettings`; Extensions uses the separate read gate
  above and does not duplicate #336's backup filter.
