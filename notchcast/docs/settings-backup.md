# Settings backup

The Notchcast Settings Backup switch defaults on and works independently of the island.
It writes one small binary property list per UTC day in the current app channel's Application
Support `fork-settings-backups` folder. A check runs on enable and hourly while enabled.
Existing daily files are preserved. Turning the switch off cancels subsequent checks.

This supplements upstream's hidden Backup feature; upstream settings remain out of scope.
The writer captures effective main-actor values, including values never written to defaults.
It reads switches with `isOn` and preferences through their getters and stores, then writes off main.
The previous statement that feature switches are excluded has been removed. Carried switches are
preferences, not capability grants: Accessibility, Calendar, microphone and other TCC grants are
never copied and continue to gate their features. Root-helper switches and `agentConfirmation`
remain excluded, as do AgentGrantStore grants, credentials, tokens and API keys.

Format 2 uses `settings-v2-<day>.plist`. Selection ignores old `settings-<day>.plist` files;
there is no format-1 compatibility path. Format 3 is refused. The selected file must be a regular file
of at most 1 MiB before reading; FIFOs and symbolic links are refused without blocking.
Restore validates every value before confirmation and again before writing. Any unknown key,
including a root or nested JSON key, wrong type, unsupported choice or out-of-range value refuses
the whole file and leaves memory and defaults unchanged. Plist booleans are distinct from numbers.
Missing keys stay untouched. Restore opens a list ordered by creation date, newest first, with sizes.
Unreadable or invalid files remain visible with a reason and a disabled Restore button.
Selecting a copy validates and holds that exact file's data through confirmation; no fallback occurs.
Switches apply through `NotchcastPreferences.set`; unwired switches present in the backup are
written as false so restore cannot enable hidden features, and a snapshot records them as false too,
so every saved value is the one a restore sets. Other values use setters and store APIs.
Declining or cancelling the dialog does not apply anything. Concurrent restore calls are ignored;
opening the folder has its own task. Missing backups show an empty state.
The command reveals the backup section. Cancelling, restoring or leaving it clears the copy list.
Open Settings Backup Folder creates and opens the folder. Both commands work with the switch off.
Restoring weather or markets can refetch from their fixed hosts when running or visible,
without credentials. Automatic retention is not applied.

## Explicit allowlist

`Model/ForkSettingsBackupSchema.swift` types no key: `allowed` and `excluded` are computed. A feature's switch is a key under its raw value, carried when the feature says `backedUp: true` and excluded when it says `false` ([feature-descriptors.md](feature-descriptors.md)); every other key lives in a `<Name>BackupKeys.swift` in the folder that owns it (one `NotchcastFeature.BackupKeys`, listed once in `NotchcastFeature.BackupKeys.all` in `Notchcast/Core/NotchcastBackupKeys.swift`). `BackupKeys` and its `BackupValue` shapes live in `Notchcast/Core/NotchcastFeature+BackupKeys.swift`, so a key file depends on the hub, never on SettingsBackup. `python3 notchcast/check-backup-schema.py` refuses a key declared twice, a key file the list does not name or that sits in a layer folder, and a switch classified zero or two times.
Live values travel in the same file: a feature's `BackupKeys` also carries `snapshot`, `apply` and, where the value shape is not enough, `validate`, and names each key through its owner's constant (in the feature's folder, or `NotchcastPreferences` for a hub-owned preference), so a renamed key cannot drop out of backups. `ForkSettingsBackupState+Live` folds the list and names no feature type; `ForkSettingsBackupRestore` reads and sets only the switches. The same checker refuses a key file whose snapshot writes, or whose apply reads, a different set of keys than it allows, and an owner constant it cannot find. A key only the backup writes (`notchcast.editor.*`, the cleanup settings blob) is a private constant of its key file.
A harness that compiles the schema without the app supplies its own `all`; the restore harness compiles the real list and checks the saved key set against the schema.
The six monitor alert thresholds take their bounds and defaults from `MonitorAlertThreshold` in `SystemMonitor/MonitorAlertsBackupKeys.swift`: the backup keys and the settings steppers read it, and the restore harness checks that `NotchcastPreferences`, which still types them, keeps the same bounds and defaults.
JSON-backed preferences travel as bounded strings with explicit nested field validation, not Data.
Optional weather and theme selections use JSON null. Theme colors and slot appearance are validated.
The low-level encoder silently drops unknown and invalid entries; the app writer supplies effective
values and skips invalid keys individually. It never copies the raw defaults domain.

| Key | Type / limits | Reason |
| --- | --- | --- |
| island | Bool | Presentation switch |
| islandExternalDisplays | Bool | Presentation switch |
| islandFullScreen | Bool | Presentation switch |
| islandHoverOpen | Bool | Presentation switch |
| islandStatusMessages | Bool | Presentation switch |
| islandLiveActivities | Bool | Presentation switch |
| launcherFromIsland | Bool | Launcher preference |
| launcherNumberKeys | Bool | Launcher preference |
| launcherAliasSpace | Bool | Launcher preference |
| monitorAlerts | Bool | Local monitor switch |
| lowDiskWarning | Bool | Warning preference |
| systemNotices | Bool | Notice preference |
| volumeLevels | Bool | TCC-gated feature preference |
| displayBrightness | Bool | TCC-gated feature preference |
| quitProtection | Bool | TCC-gated feature preference |
| liveTimers | Bool | Timer feature preference |
| dayCalendar | Bool | TCC-gated calendar preference |
| dayWeather | Bool | Weather feature preference |
| dayMarkets | Bool | Markets feature preference |
| dictationIslandHUD | Bool | Presentation switch |
| settingsBackup | Bool | Backup preference |
| showDesktop | Bool | TCC-gated feature preference |
| musicNowPlaying | Bool | Read-only now-playing observation |
| musicLastPlayer | Bool | Remembers player and routes manual media keys |
| inUseMarks | Bool | Read-only microphone/camera indicators |
| quickLookSpace | Bool | Launcher Quick Look on Space |
| markdownFiles | Bool | Editor handling of Markdown files |
| plainTextFiles | Bool | Editor handling of plain text files |
| editorSpellChecking | Bool | Editor spelling preference |
| hideCommandM | Bool | TCC-gated feature preference |
| middleClick | Bool | TCC-gated feature preference |
| greenMaximize | Bool | TCC-gated feature preference |
| eventReminder | Bool | TCC-gated calendar preference |
| switcherQuitKey | Bool | TCC-gated feature preference |
| linkQuickFixes | Bool | Manual feature preference |
| buildStats | Bool | Local snapshot feature preference |
| buildStatsPath | String, 4096 characters | Local snapshot path |
| greenMaximizeExcludedApps | String, 16384 characters | App exceptions |
| monitorCPU | Int, 10...100 | Threshold |
| monitorTemperature | Int, 40...110 | Threshold |
| monitorMemory | Int, 0...1 | Threshold mode |
| monitorDisk | Int, 1...50 | Threshold |
| monitorBattery | Int, 1...50 | Threshold |
| islandHoverDelay | 0.1, 0.3, 0.5, 1 | Known delays |
| notchcast.liveTimer.defaultDuration | 300, 600, 900, 1500, 1800, 3600 | Default duration |
| notchcast.liveTimer.playSound | Bool | Sound preference |
| notchcast.quitProtection.quitEnabled | Bool | Shortcut configuration |
| notchcast.quitProtection.closeEnabled | Bool | Shortcut configuration |
| notchcast.quitProtection.mode | String: hold, doublePress | Known modes |
| notchcast.quitProtection.exceptions | String array: 500 × 256 characters | App exceptions |
| notchcast.day.marketSymbols | String array: 100 × 64 characters | Selected symbols |
| notchcast.day.weatherPlace | JSON String ≤262144 bytes | Name/country ≤256, latitude ±90, longitude ±180 |
| notchcast.dictationCleanup.settings | JSON String ≤262144 bytes | Plain cleanup configuration; no key material |
| notchcast.appearance.surface | String: glass, black, matte | Surface style |
| notchcast.appearance.theme.backgroundOpacity | Double, 0.2...1 | Surface opacity |
| notchcast.appearance.theme.light | JSON String ≤262144 bytes | Selected light theme |
| notchcast.appearance.theme.dark | JSON String ≤262144 bytes | Selected dark theme |
| notchcast.appearance.themes.imported | JSON String ≤262144 bytes | Up to 100 themes |

Theme JSON contains only name/author (256 characters each), appearance (light/dark) and 12 hex colors.
Cleanup JSON contains only effort (low/medium/high),
promptAddition (16384 characters), and up to 500 vocabulary terms: spelling (256 characters) and
misheardForms (50 strings of 256 characters). Its API key uses a separate Keychain service and is
never read by backup. No inventoried JSON blob mixes a credential field with these plain fields.
The API key lives in a Keychain item Notchcast creates itself when the key is pasted in Settings; items made by other tools are not read. A key saved before the item moved to the `api-key` account must be pasted again.

## Exclusions

| Key or store | Reason |
| --- | --- |
| spacesOrder | Changes the macOS Spaces ordering preference |
| musicBlockAppleMusic | Terminates Apple Music after a media-key launch; changes OS app state |
| musicSharpCovers | Consent to read browser sessions and send song titles to Apple; stays on this Mac |
| spotifyConnect | Uses a saved key and starts the speaker process/network service |
| microphoneMute | Start reapplies mute to system audio devices; stop unmutes |
| archives | Start observes archivesDefaultApp and can change system-wide handlers |
| archivesDefaultApp | Changes system-wide file associations |
| torrents | Enables network transfers through an aria2 daemon |
| torrentsUseIPhone | Enables use of an additional network interface |
| torrentsKeepSharing | Enables continued uploads |
| music.lastPlayer | Runtime remembered player, not configuration |
| spotify.deviceName | Configuration of a credential-backed network speaker; retained locally |
| remoteMacAddress | Device-specific address of another Mac, like fanMode; stays on this Mac |
| microphone.muted / microphone.muted.restore | OS mute intent and device restoration state |
| archiveHandlersClaimed | OS association ownership state |
| archiveRecoveryParents | Runtime archive recovery journal locations |
| fanControl | Reaches root helper |
| batteryChargeLimit | Reaches root helper |
| batterySailing | Reaches root helper |
| batteryHeatProtection | Reaches root helper |
| batteryCalibration | Reaches root helper |
| lidClosedAwake | Reaches root helper |
| fanMode | Root fan policy; explicitly excluded |
| batteryChargePercent | Root charge policy |
| agentConfirmation | Consent gate; restore must never disable it |
| agentActionGrants / AgentGrantStore | Capability grants, in a separate consent suite |
| notchcast.liveTimer.entries | Running timer state |
| notchcast.lowDisk.isLow | Current warning spell state |
| spacesOrderOriginal | Saved system state for later restoration |
| AgentAuditStore | Runtime audit history, not a preference |
| weather cache, market quotes, monitor samples, battery state | Runtime/cache data |
| Keychain, credentials, tokens, API keys, TCC grants | Secrets and capabilities |
| Upstream preferences and stores | Upstream hidden Backup owns them |

The root-helper inventory found only BatteryModule and FanControl callers outside RootHelperClient
itself. System Monitor gates fan control; Keep Awake starts BatteryModule and can send
battery-sleep-off. `systemMonitor`, `keepAwake` and `keepAwakeMinutes` are excluded.
Cleanup enablement and baseURL are excluded nested fields and are refused on import.
Restored promptAddition changes cleanup instructions sent to the current endpoint. It can affect
punctuation, wording and formatting within DictationCleanupGuard's lexical checks; those checks
limit changes but do not guarantee semantic equivalence.

Snapshots skip individual invalid keys and log only their names. Appearance snapshots read defaults
without constructing AppearanceStore. Apply updates a running store if one exists. No store is
owned at launch today: restore constructs a temporary store to persist selections and refresh colors;
surface style uses AppStorage, and a later store reads the restored values.

Additional included keys: `pastePlain`, `finderCutPaste`, `finderRename`, `pasteImage` (Bool;
Accessibility still gates their actions), and `notchcast.colorPicker.format` (hex, hexLowercase,
rgb, hsl, swiftUIColor, nsColorLiteral).
`colorPicker` is allowed: start only enables the manual sampler. `screenshot`,
`notchcast.screenshot.destination` and `notchcast.screenshot.folder` are excluded as
screen-recording capability and capture-output policy. `backupRunNow` and `backupBrowseRestore` are
excluded: they run the machine backup tool with its repository password command.
`archivesInPlace` is excluded because it consumes the source archive, and `machineSetupProfile`
because it gates a command that changes the Dock default. Backups written before these left the
list are refused; the next daily file restores normally.
The document editor carries `notchcast.editor.font` (system/jetBrainsMono),
`notchcast.editor.theme` (system/githubDark), and `notchcast.editor.pairsAutomatically` (Bool).
Restore updates `EditorCoordinator.shared.editorPreferences`; its setters retain the bare keys
`font`, `theme`, and `pairsAutomatically` in the channel's `.editor` defaults suite.

## Adding switches

Every new `NotchcastFeature` states `backedUp: true` or `false` in its descriptor, and adds snapshot/apply wiring for any new plain store preference in the feature's `<Name>BackupKeys.swift`, listed once in `NotchcastFeature.BackupKeys.all`. `check-feature-shape.py` and `check-backup-schema.py` fail for a feature without the flag; the restore harness fails when a feature's snapshot and its allowed keys disagree.
The list (`Notchcast/Core/NotchcastBackupKeys.swift`) has a `merge=union` entry in `.gitattributes`; rerun the guard after merging.
Read `NotchcastFeature.swift` after every main merge for duplicate var headers or stray bodies,
and treat every typecheck warning as a failure, even when the shape checker passes.

Run `./Scripts/run-tests.sh nc-SettingsBackup-engine-test` for the data-loss protection harness.
Run `./Scripts/run-tests.sh nc-SettingsBackup-restore-test` for real preference restore checks.
