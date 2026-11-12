# Changelog

All notable user-visible changes to Notchcast are documented in this file. Changes to upstream Tinycast are in [its releases](https://github.com/abue-ammar/tinycast/releases).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Notchcast has no version numbers of its own: each upstream Tinycast release is rebuilt with our changes under the same tag, and the `snapshot` pre-releases are built from `main` in between. A change is listed under the first release that contained it.

## [Unreleased]

### Added

- Compress the Finder selection as ZIP, as a smaller 7z or as a faster tar.zst, from Finder's Services menu or the launcher. [#398](https://github.com/kaczordodgers/notchcast/pull/398)
- Archives unpack more formats, such as xz, bz2, zstd and other formats that bsdtar or unar can read, and ZIP files with non-Unicode Polish file names keep their names. [#400](https://github.com/kaczordodgers/notchcast/pull/400)
- Capture Area copies a selected area of the screen, on any display, to the screenshot destination. [#406](https://github.com/kaczordodgers/notchcast/pull/406)
- Capture Editor marks up a capture with arrows, text, rectangles, ellipses and blur, with undo and Copy. It opens after Capture Area, or from Edit Capture for the clipboard image or the last capture, on the capture's display. Close keeps the marks for the next Edit Capture. [#408](https://github.com/kaczordodgers/notchcast/pull/408) [#411](https://github.com/kaczordodgers/notchcast/pull/411) [#414](https://github.com/kaczordodgers/notchcast/pull/414) [#418](https://github.com/kaczordodgers/notchcast/pull/418) [#432](https://github.com/kaczordodgers/notchcast/pull/432)
- X post and article links download as Markdown files, and the island shows download progress and a message for each failed download with its reason. [#468](https://github.com/kaczordodgers/notchcast/pull/468)
- Find sharp covers for Firefox and Zen: an opt-in Music switch that shows the YouTube thumbnail for a track playing in Firefox-family browsers, which publish no artwork or a tiny one. Off by default, and nothing is read or fetched while it is off. [#489](https://github.com/kaczordodgers/notchcast/pull/489)
- AI usage island page, after Home and Day: the quota left on every Magpie account, with reset countdowns, ⌘R to refresh and ⌘P to pin. It reads the local Magpie gateway and is off by default. [#572](https://github.com/kaczordodgers/notchcast/pull/572)

### Changed

- New island and launcher design: content centered under the notch, circled status glyphs, long messages shown in full, rounded cover art, the Day calendar grouped by day, a launcher that grows out of the island, and smoother content changes. [#403](https://github.com/kaczordodgers/notchcast/pull/403)
- AI cleanup of dictation uses a local gateway at 127.0.0.1:3425 by default. A saved URL is kept. [#399](https://github.com/kaczordodgers/notchcast/pull/399)
- Toggle Island opens the island pinned until Escape or the command again, and Hyper+S is its default shortcut when that chord is free. [#480](https://github.com/kaczordodgers/notchcast/pull/480)
- The launcher stays open while a screenshot is taken and takes the keyboard back afterwards. [#481](https://github.com/kaczordodgers/notchcast/pull/481)
- Spaces order is set only by the Spaces order switch; the matching Tweaks item is removed so the two no longer fight. [#429](https://github.com/kaczordodgers/notchcast/pull/429)
- The launcher opened from the island is Tinycast's glass panel again: it follows Light and Dark, keeps its shadow and hangs just below the island instead of turning black and covering the menu bar. [#508](https://github.com/kaczordodgers/notchcast/pull/508)
- Convert Files makes ZIP and 7z archives and extracts through Archives, so it names them the same way (zipping report.pdf gives report.pdf.zip) and gets the same safety checks when extracting. [#562](https://github.com/kaczordodgers/notchcast/pull/562)

### Fixed

- Spotify Connect Speaker Off no longer hides Speaker On, and On starts the speaker directly. [#397](https://github.com/kaczordodgers/notchcast/pull/397)
- Typing the Shorten Link alias and Space moves to its Link field instead of running it without a link. [#390](https://github.com/kaczordodgers/notchcast/pull/390)
- Clean System finds system caches and diagnostic reports. [#394](https://github.com/kaczordodgers/notchcast/pull/394)
- The low disk alert checks only the startup disk, alerts use light sampling while the Monitor page is closed, and changing a threshold no longer repeats an alert within its cooldown. [#393](https://github.com/kaczordodgers/notchcast/pull/393)
- Saving dictation cleanup settings no longer turns the feature off after relaunch. A cleanup API key saved before this change must be pasted again. [#402](https://github.com/kaczordodgers/notchcast/pull/402)
- Updates install the newest Notchcast snapshot instead of a mirrored upstream beta. [#427](https://github.com/kaczordodgers/notchcast/pull/427)
- Mac Link recovers by itself after its listener or peer discovery fails, without toggling it or relaunching. [#485](https://github.com/kaczordodgers/notchcast/pull/485)
- Voice Ask keeps working after a key release that Secure Input hid. [#486](https://github.com/kaczordodgers/notchcast/pull/486)
- Transcript downloads work for real video links, and starting one download no longer cancels another. [#468](https://github.com/kaczordodgers/notchcast/pull/468)
- Capture Text rejoins words split by a hyphen at a line break when punctuation or quotes, including German and French quotes, follow. [#439](https://github.com/kaczordodgers/notchcast/pull/439) [#445](https://github.com/kaczordodgers/notchcast/pull/445)
- Scrolling Capture no longer crops or loses rows next to headers, footers and flat margins. [#442](https://github.com/kaczordodgers/notchcast/pull/442) [#447](https://github.com/kaczordodgers/notchcast/pull/447)
- The system monitor keeps CPU and GPU temperature sensors after a failed lookup and ranks every process, not only the first ones it reaches. [#440](https://github.com/kaczordodgers/notchcast/pull/440) [#441](https://github.com/kaczordodgers/notchcast/pull/441) [#449](https://github.com/kaczordodgers/notchcast/pull/449) [#450](https://github.com/kaczordodgers/notchcast/pull/450)
- Accessory connection notices no longer show a device as connected after a disconnect that was missed or happened at startup. [#438](https://github.com/kaczordodgers/notchcast/pull/438) [#446](https://github.com/kaczordodgers/notchcast/pull/446)
- The walking pad starts a new walk and toggles correctly after it did not answer a Stop. [#443](https://github.com/kaczordodgers/notchcast/pull/443) [#448](https://github.com/kaczordodgers/notchcast/pull/448) [#451](https://github.com/kaczordodgers/notchcast/pull/451)
- An agent confirmation nobody answers closes at its deadline, so later agent requests are shown again. [#475](https://github.com/kaczordodgers/notchcast/pull/475)
- Clean shows "Needs the Notchcast helper update" when the helper is outdated, Disk counts nested selections once, and cut error output ends with [truncated]. [#524](https://github.com/kaczordodgers/notchcast/pull/524) [#530](https://github.com/kaczordodgers/notchcast/pull/530)
- "Show library" is back in Settings search. [#512](https://github.com/kaczordodgers/notchcast/pull/512)
- The task sync failure message no longer promises a retry that does not exist. [#488](https://github.com/kaczordodgers/notchcast/pull/488)
- Copy Path, Clear Notifications, Generate Password, Shorten Link, Switch Noise Control and AirDrop Selected Files say what went wrong instead of one generic error. [#537](https://github.com/kaczordodgers/notchcast/pull/537)
- Compressing to an exFAT or network volume works, and a name already taken gets one number, such as x (2).pdf instead of x (2) (2).pdf. [#541](https://github.com/kaczordodgers/notchcast/pull/541)
- Clean reports an Optimize tool that timed out, and odd characters in a tool's output no longer fail the run. [#534](https://github.com/kaczordodgers/notchcast/pull/534)
- Capture Screen says when the display is no longer there instead of doing nothing. [#571](https://github.com/kaczordodgers/notchcast/pull/571)

## [v0.12.8.snapshot.20261105211139] - 2026-11-05

### Fixed

- Dictation history keeps text that was typed in with Live Insertion. [#376](https://github.com/kaczordodgers/notchcast/pull/376)

## [v0.12.8.snapshot.20261105202138] - 2026-11-05

### Fixed

- The Soloist music queue no longer refreshes its reply in a loop. [#374](https://github.com/kaczordodgers/notchcast/pull/374)

## [v0.12.8.snapshot.20261105193137] - 2026-11-05

No user-visible changes.

## [v0.12.8.snapshot.20261105184136] - 2026-11-05

No user-visible changes.

## [v0.12.8.snapshot.20261105162623] - 2026-11-05

No user-visible changes.

## [v0.12.8.snapshot.20261105153622] - 2026-11-05

### Removed

- Command Runner is hidden until it has a way to add commands. [#368](https://github.com/kaczordodgers/notchcast/pull/368)

## [v0.12.8.snapshot.20261105144621] - 2026-11-05

No user-visible changes.

## [v0.12.8.snapshot.20261105135620] - 2026-11-05

### Added

- A window that shows the dictation history. [#363](https://github.com/kaczordodgers/notchcast/pull/363)

### Changed

- A newer release installs and restarts Notchcast right away instead of waiting for the Mac to be idle. [#365](https://github.com/kaczordodgers/notchcast/pull/365)

## [v0.12.8.snapshot.20261105125423] - 2026-11-05

### Added

- A Shelf screen for items received from the other Mac. [#362](https://github.com/kaczordodgers/notchcast/pull/362)
- Choose which settings backup to restore. [#358](https://github.com/kaczordodgers/notchcast/pull/358)

### Changed

- Spotify Connect errors say what went wrong, and Download always offers a retry. [#361](https://github.com/kaczordodgers/notchcast/pull/361)

### Removed

- Tinycast's Backup tab and Raycast import are hidden. [#360](https://github.com/kaczordodgers/notchcast/pull/360)

### Fixed

- The Island switch can be turned back on while the island is off. [#359](https://github.com/kaczordodgers/notchcast/pull/359)
- AI chat keeps using tools until the task is done or blocked. [#357](https://github.com/kaczordodgers/notchcast/pull/357)

## [v0.12.8.snapshot.20261105112811] - 2026-11-05

### Added

- Backup actions in the Backups settings tab. [#356](https://github.com/kaczordodgers/notchcast/pull/356)

### Changed

- Island notices show one after another instead of replacing each other. [#352](https://github.com/kaczordodgers/notchcast/pull/352)

### Removed

- Unused Tinycast features are hidden: Raycast extensions, fallbacks, Apple Shortcuts and the donation window. [#353](https://github.com/kaczordodgers/notchcast/pull/353)

### Fixed

- Cancelling an archive extraction stops promptly. [#277](https://github.com/kaczordodgers/notchcast/pull/277)
- Restoring a settings backup can no longer turn on hidden features. [#336](https://github.com/kaczordodgers/notchcast/pull/336)

## [v0.12.8.snapshot.20261105103724] - 2026-11-05

### Added

- Escape discards a dictation. [#337](https://github.com/kaczordodgers/notchcast/pull/337)

### Changed

- Shorten Link accepts a typed link. [#355](https://github.com/kaczordodgers/notchcast/pull/355)
- Shorten Link uses the front browser's address or the selected text before the clipboard. [#345](https://github.com/kaczordodgers/notchcast/pull/345)

### Fixed

- Brightness keys work again, and the protection switches stay in Settings. [#344](https://github.com/kaczordodgers/notchcast/pull/344)
- Brightness key presses made before Notchcast is ready are no longer lost. [#347](https://github.com/kaczordodgers/notchcast/pull/347)
- Green Button Maximizes handles hovering over the green button and windows with unusual controls. [#333](https://github.com/kaczordodgers/notchcast/pull/333)

## [v0.12.8.snapshot.20261105091448] - 2026-11-05

### Added

- Number badges on the first nine launcher results. [#334](https://github.com/kaczordodgers/notchcast/pull/334)
- Walking pad commands in the launcher. [#256](https://github.com/kaczordodgers/notchcast/pull/256)
- Fleet Panel for T3 Code threads on paired Macs. [#312](https://github.com/kaczordodgers/notchcast/pull/312)

### Fixed

- Trackpad middle click reaches the app under the pointer. [#340](https://github.com/kaczordodgers/notchcast/pull/340)

## [v0.12.8.snapshot.20261105072628] - 2026-11-05

### Added

- Katana amp channel commands in the launcher. [#253](https://github.com/kaczordodgers/notchcast/pull/253)

### Changed

- MCP Server, AI Chat Tools, Voice Ask, Link Quick Fixes, system root cleaning and Screen Recording are back in Settings. [#316](https://github.com/kaczordodgers/notchcast/pull/316)
- Disk cleanup refuses folders that changed or could not be fully read since the scan. [#288](https://github.com/kaczordodgers/notchcast/pull/288)

### Fixed

- Shelf sends every request and cleans up received files. [#291](https://github.com/kaczordodgers/notchcast/pull/291)
- Trackpad middle click works again after the Mac wakes. [#282](https://github.com/kaczordodgers/notchcast/pull/282)
- Spell checking in an open Notes editor follows its switch. [#281](https://github.com/kaczordodgers/notchcast/pull/281)
- Finder commands read selected paths correctly. [#271](https://github.com/kaczordodgers/notchcast/pull/271)

## [v0.12.8] - 2026-11-05

Upstream Tinycast [0.12.8](https://github.com/abue-ammar/tinycast/releases/tag/v0.12.8), rebuilt with the Notchcast changes on `main` at build time. Those changes are listed under the snapshots.

## [v0.12.7-beta.131.snapshot.20261105055618] - 2026-11-05

### Added

- Agent Island: a summary of waiting and working agents. [#305](https://github.com/kaczordodgers/notchcast/pull/305)
- Sync tasks between two Macs over Mac Link. [#318](https://github.com/kaczordodgers/notchcast/pull/318)

### Fixed

- Turning off a command's switch releases its modifier keys and hotkey conflicts. [#315](https://github.com/kaczordodgers/notchcast/pull/315)

## [v0.12.8-beta.132] - 2026-11-05

Upstream Tinycast [0.12.8-beta.132](https://github.com/abue-ammar/tinycast/releases/tag/v0.12.8-beta.132), rebuilt with the Notchcast changes on `main` at build time. Those changes are listed under the snapshots.

## [v0.12.7-beta.131.snapshot.20261105041429] - 2026-11-05

### Added

- Alerts when an agent needs your approval or an answer. [#302](https://github.com/kaczordodgers/notchcast/pull/302)

### Changed

- Updates wait until the Mac is idle before installing (reverted by [#365](https://github.com/kaczordodgers/notchcast/pull/365)). [#307](https://github.com/kaczordodgers/notchcast/pull/307)

### Fixed

- Cancelling a screenshot keeps what was on the clipboard. [#264](https://github.com/kaczordodgers/notchcast/pull/264)
- Settings no longer stalls while it checks permissions. [#293](https://github.com/kaczordodgers/notchcast/pull/293)
- The theme command can take a hotkey and a deeplink. [#278](https://github.com/kaczordodgers/notchcast/pull/278)
- Stopping dictation can no longer hang. [#279](https://github.com/kaczordodgers/notchcast/pull/279)
- The Katana amp ignores stale MIDI replies. [#270](https://github.com/kaczordodgers/notchcast/pull/270)

## [v0.12.7-beta.131.snapshot.20261105021056] - 2026-11-05

### Added

- OpenBot Agents: waiting items from local OpenBot agents. [#249](https://github.com/kaczordodgers/notchcast/pull/249)
- Agent Threads: active and recently finished agent threads on this Mac. [#248](https://github.com/kaczordodgers/notchcast/pull/248)
- Notchcast's launcher commands are available to local agents. [#283](https://github.com/kaczordodgers/notchcast/pull/283)
- Screen recording commands in the launcher. [#238](https://github.com/kaczordodgers/notchcast/pull/238)
- Bluetooth walking pad control. [#233](https://github.com/kaczordodgers/notchcast/pull/233)

### Fixed

- A switched-off feature releases its command hotkeys. [#289](https://github.com/kaczordodgers/notchcast/pull/289)
- Complete Next Task moves a repeating task to its next date. [#276](https://github.com/kaczordodgers/notchcast/pull/276)
- Todoist import creates labels that are missing from the export. [#280](https://github.com/kaczordodgers/notchcast/pull/280)
- Day launcher commands respect the Day switches. [#292](https://github.com/kaczordodgers/notchcast/pull/292)
- A charge limit turned off by another app stays off. [#267](https://github.com/kaczordodgers/notchcast/pull/267)
- Unmuting restores each microphone's original channels. [#265](https://github.com/kaczordodgers/notchcast/pull/265)
- Two transcript downloads at once no longer overwrite each other. [#269](https://github.com/kaczordodgers/notchcast/pull/269)
- Katana preset names with numbers out of range are rejected. [#262](https://github.com/kaczordodgers/notchcast/pull/262)
- Dock settings headings use sentence case and one caption size. [#255](https://github.com/kaczordodgers/notchcast/pull/255)

## [v0.12.7-beta.131.snapshot.20261104235523] - 2026-11-05

### Added

- Accessory connection and low battery notices. [#242](https://github.com/kaczordodgers/notchcast/pull/242)

### Changed

- Settings has a Notchcast category with one tab per area, and each switch shows its commands under it. [#212](https://github.com/kaczordodgers/notchcast/pull/212)
- Agent requests are confirmed in Tinycast's standard dialog. [#236](https://github.com/kaczordodgers/notchcast/pull/236)

## [v0.12.7-beta.131.snapshot.20261104221037] - 2026-11-04

### Added

- Voice Ask: ask a question by voice. [#227](https://github.com/kaczordodgers/notchcast/pull/227)
- System root cleaning in Clean. [#235](https://github.com/kaczordodgers/notchcast/pull/235)

## [v0.12.7-beta.131.snapshot.20261104195502] - 2026-11-04

### Added

- Shuffle, repeat and the Soloist queue for music. [#220](https://github.com/kaczordodgers/notchcast/pull/220)
- Big downloads can use Wi-Fi and a plugged-in iPhone together. [#222](https://github.com/kaczordodgers/notchcast/pull/222)
- Mac Link quick fixes for connection problems. [#229](https://github.com/kaczordodgers/notchcast/pull/229)
- Eject a disk from the system monitor. [#224](https://github.com/kaczordodgers/notchcast/pull/224)
- An MCP server and Notchcast tools in AI chat. [#221](https://github.com/kaczordodgers/notchcast/pull/221)

## [v0.12.7-beta.131.snapshot.20261104190108] - 2026-11-04

### Added

- Katana amp control over MIDI. [#216](https://github.com/kaczordodgers/notchcast/pull/216)

## [v0.12.7-beta.131.snapshot.20261104144827] - 2026-11-04

No user-visible changes.

## [v0.12.7-beta.131.snapshot.20261104123848] - 2026-11-04

### Changed

- Every Notchcast switch now does something you can find by name, or stays out of Settings until it does. Clear Notifications, Copy Path, Generate Password, Shorten Link, Switch Noise Control, AirDrop Selected Files and Send Clipboard to Other Mac became commands, and volume and brightness keys show their levels in the island. [#209](https://github.com/kaczordodgers/notchcast/pull/209)
- Notchcast's background jobs show their own names in Login Items. [#197](https://github.com/kaczordodgers/notchcast/pull/197)

## [v0.12.7-beta.131.snapshot.20261104113251] - 2026-11-04

### Added

- Themes and surface styles, paste tools, a local agent bridge with a command line tool, and the walking pad and Katana amp foundations. [#178](https://github.com/kaczordodgers/notchcast/pull/178)

### Fixed

- Quitting no longer waits on a stuck privileged helper. [#201](https://github.com/kaczordodgers/notchcast/pull/201)
- Paste Plain Text uses one module, and older settings backups restore dictation cleanup settings. [#202](https://github.com/kaczordodgers/notchcast/pull/202)

## [v0.12.7-beta.131.snapshot.20261104082642] - 2026-11-04

### Added

- Monitor alerts, audio device priority, Clean, system tools and macOS tweaks. [#188](https://github.com/kaczordodgers/notchcast/pull/188)

### Fixed

- Dictation capture no longer blocks other work. [#194](https://github.com/kaczordodgers/notchcast/pull/194)

## [v0.12.7-beta.131.snapshot.20261104072215] - 2026-11-04

The first build with Notchcast's own features.

### Added

- The island: a Dynamic Island in the notch, or a pill on displays without one, with Home and Day pages and live activities. [#37](https://github.com/kaczordodgers/notchcast/pull/37)
- The launcher opens under the island. [#32](https://github.com/kaczordodgers/notchcast/pull/32)
- Island page commands: ⌘R refreshes, ⌘P pins. [#129](https://github.com/kaczordodgers/notchcast/pull/129)
- Low disk warnings, system notices, volume in the island, display brightness, quit protection and timers. [#47](https://github.com/kaczordodgers/notchcast/pull/47)
- Now playing, Spotify Connect and microphone mute. [#48](https://github.com/kaczordodgers/notchcast/pull/48)
- Music commands, torrents and archives. [#182](https://github.com/kaczordodgers/notchcast/pull/182)
- System monitor, fan control, battery and energy settings. [#75](https://github.com/kaczordodgers/notchcast/pull/75)
- Charge limit, Spotlight indexing and Touch ID for `sudo` through a privileged helper. [#67](https://github.com/kaczordodgers/notchcast/pull/67)
- Download video, audio and transcripts. [#45](https://github.com/kaczordodgers/notchcast/pull/45)
- Save webpages as Markdown. [#55](https://github.com/kaczordodgers/notchcast/pull/55)
- Downloads and Distill settings and commands, Convert Files, Media Tools, URL cleaner, launcher tools, Mac Link and the remote Mac commands. [#187](https://github.com/kaczordodgers/notchcast/pull/187)
- Screenshots and the color picker. [#141](https://github.com/kaczordodgers/notchcast/pull/141)
- Capture Text, Scrolling Capture, Globe dictation, English dictation and Notchcast tools in AI chat. [#195](https://github.com/kaczordodgers/notchcast/pull/195)
- Dictation status in the island. [#149](https://github.com/kaczordodgers/notchcast/pull/149)
- AI cleanup of dictation transcripts. [#76](https://github.com/kaczordodgers/notchcast/pull/76)
- Paste Plain Text, Paste Image in Finder and other Finder tools. [#184](https://github.com/kaczordodgers/notchcast/pull/184)
- Markdown Quick Look, Finder cut and paste, and Finder rename. [#179](https://github.com/kaczordodgers/notchcast/pull/179)
- Settings backups, calendar event reminders in the island, and Q to quit an app from the window switcher. [#142](https://github.com/kaczordodgers/notchcast/pull/142)
- Restore settings backups. [#191](https://github.com/kaczordodgers/notchcast/pull/191)
- Tasks: a local task manager with recurrence, quick add, reminders and Todoist import. [#192](https://github.com/kaczordodgers/notchcast/pull/192)
- Launcher number keys and Space after an alias. [#163](https://github.com/kaczordodgers/notchcast/pull/163)

### Changed

- Running a command from a deep link asks first. [#105](https://github.com/kaczordodgers/notchcast/pull/105)
- Installing an update rolls back to the previous build if the new one fails to start. [#104](https://github.com/kaczordodgers/notchcast/pull/104)

## [v0.12.7-beta.131] - 2026-11-03

Upstream Tinycast [0.12.7-beta.131](https://github.com/abue-ammar/tinycast/releases/tag/v0.12.7-beta.131), rebuilt with the Notchcast changes on `main` at build time. No user-visible Notchcast changes since the previous release.

## [v0.12.6-beta.130] - 2026-11-03

Upstream Tinycast [0.12.6-beta.130](https://github.com/abue-ammar/tinycast/releases/tag/v0.12.6-beta.130), rebuilt as the first Notchcast release. These changes were committed directly, before the fork used pull requests.

### Added

- Notchcast's own name, bundle id `app.notchcast` and `notchcast://` URL scheme, so it runs beside Tinycast.
- The app checks this repository's releases for updates.
- The installer copies Tinycast Beta's settings and data to Notchcast once.

[Unreleased]: https://github.com/kaczordodgers/notchcast/compare/v0.12.8.snapshot.20261105211139...main
[v0.12.8.snapshot.20261105211139]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105211139
[v0.12.8.snapshot.20261105202138]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105202138
[v0.12.8.snapshot.20261105193137]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105193137
[v0.12.8.snapshot.20261105184136]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105184136
[v0.12.8.snapshot.20261105162623]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105162623
[v0.12.8.snapshot.20261105153622]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105153622
[v0.12.8.snapshot.20261105144621]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105144621
[v0.12.8.snapshot.20261105135620]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105135620
[v0.12.8.snapshot.20261105125423]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105125423
[v0.12.8.snapshot.20261105112811]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105112811
[v0.12.8.snapshot.20261105103724]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105103724
[v0.12.8.snapshot.20261105091448]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105091448
[v0.12.8.snapshot.20261105072628]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8.snapshot.20261105072628
[v0.12.8]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8
[v0.12.7-beta.131.snapshot.20261105055618]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261105055618
[v0.12.8-beta.132]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.8-beta.132
[v0.12.7-beta.131.snapshot.20261105041429]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261105041429
[v0.12.7-beta.131.snapshot.20261105021056]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261105021056
[v0.12.7-beta.131.snapshot.20261104235523]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261104235523
[v0.12.7-beta.131.snapshot.20261104221037]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261104221037
[v0.12.7-beta.131.snapshot.20261104195502]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261104195502
[v0.12.7-beta.131.snapshot.20261104190108]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261104190108
[v0.12.7-beta.131.snapshot.20261104144827]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261104144827
[v0.12.7-beta.131.snapshot.20261104123848]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261104123848
[v0.12.7-beta.131.snapshot.20261104113251]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261104113251
[v0.12.7-beta.131.snapshot.20261104082642]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261104082642
[v0.12.7-beta.131.snapshot.20261104072215]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131.snapshot.20261104072215
[v0.12.7-beta.131]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.7-beta.131
[v0.12.6-beta.130]: https://github.com/kaczordodgers/notchcast/releases/tag/v0.12.6-beta.130
