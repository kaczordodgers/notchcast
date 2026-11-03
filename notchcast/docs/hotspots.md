# Coupling and upstream churn

HEAD: `3be769dc1558e065b39a97dfb8b0e32f3db0a3a9`; churn since 2026-05-07T16:10:51.401105+00:00.

Score = incoming file count × commits touching file in the last 180 days.

| File | Fan-in | Fan-out | Churn | Score |
| --- | ---: | ---: | ---: | ---: |
| `Tinycast/DesignSystem/Theme.swift` | 182 | 0 | 66 | 12012 |
| `Tinycast/App/AppCore.swift` | 87 | 134 | 96 | 8352 |
| `Tinycast/Features/Settings/AppSettings.swift` | 66 | 24 | 66 | 4356 |
| `Tinycast/Features/Launcher/Service/AppIndex.swift` | 54 | 37 | 51 | 2754 |
| `Tinycast/Palette/PaletteState.swift` | 57 | 5 | 29 | 1653 |
| `Tinycast/Features/HotKeys/Service/HotKeyManager.swift` | 28 | 12 | 34 | 952 |
| `Tinycast/Features/Launcher/Model/CommandID.swift` | 28 | 3 | 33 | 924 |
| `Tinycast/DesignSystem/PopoverMenu.swift` | 40 | 5 | 23 | 920 |
| `Tinycast/DesignSystem/SettingsComponents.swift` | 35 | 7 | 24 | 840 |
| `Tinycast/Palette/PaletteCoordinator.swift` | 24 | 9 | 26 | 624 |
| `Tinycast/Palette/PaletteScreen.swift` | 27 | 6 | 23 | 621 |
| `Tinycast/Features/Clipboard/Model/ClipboardStore.swift` | 24 | 3 | 25 | 600 |
| `Tinycast/Features/HotKeys/Model/HotKeyAction.swift` | 28 | 4 | 19 | 532 |
| `Tinycast/Palette/PaletteWindowController.swift` | 8 | 22 | 65 | 520 |
| `Tinycast/Features/AI/Model/AIConnection.swift` | 29 | 1 | 16 | 464 |
| `Tinycast/Platform/Images/IconCache.swift` | 30 | 0 | 14 | 420 |
| `Tinycast/DesignSystem/InterfaceMetrics.swift` | 26 | 1 | 16 | 416 |
| `Tinycast/Features/Launcher/Service/VisibilityStore.swift` | 23 | 2 | 17 | 391 |
| `Tinycast/Platform/Permissions.swift` | 33 | 2 | 10 | 330 |
| `Tinycast/Features/Settings/AppSettingsKey.swift` | 5 | 0 | 62 | 310 |
| `Tinycast/Features/Backup/Model/SettingsBackup.swift` | 5 | 24 | 55 | 275 |
| `Tinycast/DesignSystem/Scrolling/ScrollIntent.swift` | 44 | 0 | 6 | 264 |
| `Tinycast/Features/Clipboard/Service/Paster.swift` | 22 | 4 | 12 | 264 |
| `Tinycast/Features/Settings/SettingsTab.swift` | 13 | 0 | 19 | 247 |
| `Tinycast/Features/AI/Model/AIRequest.swift` | 26 | 2 | 9 | 234 |
| `Tinycast/Features/Launcher/Service/AppLauncher.swift` | 18 | 0 | 13 | 234 |
| `Tinycast/Palette/PaletteMode.swift` | 12 | 2 | 19 | 228 |
| `Tinycast/Features/AI/UI/AIChatCoordinator.swift` | 7 | 38 | 32 | 224 |
| `Tinycast/Features/Launcher/Model/SearchRelevance.swift` | 17 | 0 | 13 | 221 |
| `Tinycast/Features/Settings/SettingsAnchor.swift` | 9 | 1 | 24 | 216 |

## Registry enums

| Registry | File | Fan-in |
| --- | --- | ---: |
| CommandID | `Tinycast/Features/Launcher/Model/CommandID.swift` | 28 |
| SettingsTab | `Tinycast/Features/Settings/SettingsTab.swift` | 13 |
| PaletteMode | `Tinycast/Palette/PaletteMode.swift` | 12 |
| SettingsFileKey | `Tinycast/Features/Settings/Model/SettingsFileKey.swift` | 8 |
| HotKeyAction | `Tinycast/Features/HotKeys/Model/HotKeyAction.swift` | 28 |

Lexical approximation; ambiguous names resolve to all primary declaration files; extensions are not reference targets. Declaration names except extension targets excluded from references. Nested declarations and typealiases not indexed. Strings including interpolations and comments stripped. Regex literals not parsed. No target/conditional compilation resolution. Churn counts reachable commits, no rename following.
