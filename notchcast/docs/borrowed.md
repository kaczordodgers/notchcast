# Borrowed code

The one list of outside code, data and engines Notchcast took from projects other than upstream Tinycast. A weekly watch reads the table below, compares each upstream against the pinned version and reports only changes worth acting on: fixes or security changes in code we took, behaviour changes in an engine we run, and new features worth a look. Upstream Tinycast is not listed: the `sync` workflow covers it. A new borrowed source is added here in the same commit that brings it in.

Kinds: **port** copies or adapts code, so the watch reads upstream commits touching the watched paths; **data** copies generated data, so the watch reads changes to that data; **engine** is an outside program we run, so the watch reads releases and tags; **reference** borrows behaviour or design only, so the watch reads releases and notable commits on the watched paths.

Pinned is the upstream commit or version our copy matches. `unrecorded` means no pin was kept; the watch then reports upstream changes since 2026-11-07, when the current history of our tree starts. After porting an upstream change, set Pinned to that upstream commit in the same commit.

## Sources

| Key | Upstream | Kind | Pinned | Our tree | Watched upstream paths |
| --- | --- | --- | --- | --- | --- |
| vorssaint-music | https://github.com/vorssaint/vorssaint-utils | port | 794608a | `Tinycast/Features/Music/NowPlayingAdapter/`, `Music/Service/{SystemNowPlayingSource,PlayerApps,MusicLaunchBlocker}.swift`, `Music/Model/MusicLaunchPolicy.swift` | `Sources/NowPlayingAdapter/`, `Resources/now-playing.pl`, `Sources/Vorssaint/Services/Audio/MusicLaunch*`, `Sources/Vorssaint/Services/Notch/NotchMusic*` |
| vorssaint-monitor | https://github.com/vorssaint/vorssaint-utils | port | 833967fd | `Tinycast/Features/SystemMonitor/Model/{BatteryReading,CPUTicks,TemperatureSensorPolicy}.swift`, `SystemMonitor/Service/{BatteryPeripheralService,DiskSampler}.swift` | `Sources/Vorssaint/Services/Metrics/`, `Sources/Vorssaint/Services/SystemMonitor/` |
| vorssaint-audio | https://github.com/vorssaint/vorssaint-utils | port | 833967fd | `Tinycast/Features/AudioPriority/` | `Sources/Vorssaint/Services/Audio/AudioPriorityService.swift`, `Sources/Vorssaint/Services/Audio/AudioInputDeviceManager.swift` |
| vorssaint-browser-covers | https://github.com/vorssaint/vorssaint-utils | port | 833967fd | `Tinycast/Features/Music/Model/BrowserCoverRules.swift`, `Music/Service/BrowserCover{Finder,Sources}.swift` | `Sources/Vorssaint/Services/Notch/NotchBrowserArtwork*` |
| vorssaint-cleaning-mode | https://github.com/vorssaint/vorssaint-utils | port | 833967fd | `Tinycast/Features/CleaningMode/` | `Sources/Vorssaint/Services/CleaningMode/` |
| vorssaint-pricing | https://github.com/vorssaint/vorssaint-utils | data | unrecorded | `Tinycast/Features/AgentSessions/Pricing/` | `Resources/agent-prices.json`, `Sources/Vorssaint/Services/AgentUsage/AgentPric*` |
| vorssaint-capture | https://github.com/vorssaint/vorssaint-utils | reference | unrecorded | `Tinycast/Features/Capture{Area,Editor,Recording,Screenshot,Scrolling,Trimmer}/` | `Sources/Vorssaint/Services/Recorder/`, `Sources/Vorssaint/Services/QuickTools/Screenshot*` |
| vorssaint-media | https://github.com/vorssaint/vorssaint-utils | reference | unrecorded | `Tinycast/Features/MediaTools/` | `Sources/Vorssaint/Services/Media/` |
| media-converter | https://github.com/raycast/extensions | port | 88966c62 | `Tinycast/Features/ConvertFiles/` | `extensions/media-converter/src/types/media.ts`, `extensions/media-converter/src/utils/converter.ts` |
| removemacai | https://github.com/omlahore/RemoveMacAI | port | b6ecada4 | `Tinycast/Features/Tweaks/Model/` | `Sources/removemacai/` |
| batfi | https://github.com/rurza/BatFi | port | bbe0197 | `notchcast/root/NativeChargeLimit.swift` | `Server/ManualChargeLimitDefaults.swift`, `Server/PowerUICharging.swift`, `investigation/tools/mclset.swift` |
| purge-app | https://github.com/jithin-sabu/purge-app | port | b2d38648 | `Tinycast/Features/Clean/Model/CleanPurgeRule.swift` | whole repo (project rules) |
| ray-so | https://github.com/raycast/ray-so | data | 168f9aa9c2c4 | `Tinycast/Features/Appearance/Model/RaycastThemeCatalog.swift` | `app/(navigation)/themes/` |
| hatchzip | https://github.com/xevrion/hatchzip | engine | 0.1.3 | `Tinycast/Features/Archives/` | releases and tags; `crates/core/src/` |
| mole | https://github.com/tw93/Mole | reference | 8c55e8c0 | `Tinycast/Features/Clean/` | `bin/purge.sh`, `lib/clean/`, `cmd/analyze/` |
| petal | https://github.com/henrydennis/petal | reference | unrecorded | `Tinycast/Features/Clean/Service/CleanDiskDirectoryReader.swift` | `dirlist.rs` |
| odysseus | https://github.com/odysseus-dev/odysseus | reference | unrecorded | `Tinycast/Features/AgentChatTools/Model/AgentTurnCompletion.swift` | `src/agent_loop.py` (branch `dev`) |
| launcher-keys | https://github.com/sermelipharo/tinycast-space and https://github.com/seancxk/tinycast-fork | reference | unrecorded | `Tinycast/Features/Launcher/Keys/` | `.space/patches/0001-alias-space.patch`, `.space/patches/0016-launcher-keys.patch`; `patches/0001-alias-space.patch` |
| net-merge | https://github.com/rohit267/net-merge | reference | unrecorded | `Tinycast/Features/NetMerge/` | releases; `internal/` |
