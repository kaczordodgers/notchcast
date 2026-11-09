<!-- Source of the root README.md: `notchcast/ci.py regenerate` copies this file there, so edit this one.
     Links use repository-root paths (/LICENSE) so they work in both places. Maintainer docs: notchcast/README.md. -->

# Notchcast

[![Release](https://img.shields.io/github/v/release/kaczordodgers/notchcast)](https://github.com/kaczordodgers/notchcast/releases/latest)
[![Sync](https://github.com/kaczordodgers/notchcast/actions/workflows/sync.yml/badge.svg)](https://github.com/kaczordodgers/notchcast/actions/workflows/sync.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](/LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-lightgrey)

A native macOS launcher with a Dynamic Island in the notch, plus clipboard history, hotkeys, capture, dictation and system tools in one app.

<!-- TODO hero image: no shipped-UI screenshot of Notchcast exists yet. Add a light and a dark capture of the
     open island and the launcher under docs/notchcast/ and reference them here with <picture>. -->

Notchcast is a modified fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar. It is upstream Tinycast plus our own features on top, rebuilt automatically whenever upstream moves. See [Credits](#credits).

[Download](https://github.com/kaczordodgers/notchcast/releases) · [Changelog](/CHANGELOG.md) · [Build from source](#build-from-source) · [Maintaining the fork](/notchcast/README.md)

## Features

Everything Notchcast adds is in **Settings → Notchcast**, one tab per area. Each feature has its own switch, and its launcher commands sit under it. Turning a switch off also removes its commands and hotkeys.

<!-- features:start -->
<!-- Generated and updated by the daily changelog job: list only features with a working, visible switch on main.
     Switches in NotchcastFeature.unwired and the hidden upstream features in notchcast/docs/hidden.md are not features. -->

### Island

- A Dynamic Island around the notch, or a small pill on displays without one, on the built-in and external displays and over full-screen apps.
- Home and Day pages: live activities, status messages, progress with Cancel, calendar events and calendar reminders. ⌘R refreshes a page, ⌘P pins the island open.
- Opens on hover or by command, and opens the launcher right under it.
- Volume and brightness levels, now playing, dictation status, timers, low disk and Wi-Fi, Tailscale and battery notices show in the island.

### Launcher

- Everything from Tinycast's launcher (see [From Tinycast](#from-tinycast)).
- ⌘1–⌘9 opens the first nine results; Space after an exact alias opens its command; Space on a file result opens Quick Look.
- Q in an empty window search quits the selected app.
- Clear Notifications, Copy Path, Generate Password, Shorten Link, Switch Noise Control and AirDrop Selected Files.
- Themes and surface styles for the launcher, dialogs and HUDs.

### Files and clipboard

- ⌘X and ⌘V move files in Finder; Hyper+R renames the selection; ⌘V saves a clipboard image as a PNG file in Finder.
- Paste Plain Text, and tracking parameters removed from copied links.
- Archives in many formats extract beside the original, optionally in place and as the default app for archives. Compress the Finder selection as ZIP, 7z or tar.zst.
- Convert files, compress video and images, make GIFs and extract text from the Finder selection, all locally.
- Quick Look for Markdown files, and spell checking in the editor.

### Capture

- Screenshots and screen recordings of an area, window or display, with system audio.
- Capture Text (offline OCR), Scrolling Capture and a color picker.

### Dictation

- Globe key dictation: tap to start or finish, hold to talk. Escape discards.
- Optional AI cleanup of the transcript, English dictation and a dictation history.

### Music and sound

- Now playing in the island, controls that go to the last active player, and media keys that no longer launch Apple Music.
- This Mac as a Spotify Connect speaker.
- Volume overlay in the island, automatic audio device priority and F5 to mute every microphone.
- Channel switching for a Boss Katana amp over MIDI.

### Day and tasks

- Local tasks with recurrence, quick add, reminders and Todoist import, synced between two Macs.
- Countdown timers and alarms in the island.

### System

- System monitor, fan control, monitor alerts and ejecting a disk.
- Battery charge limit, sailing, heat protection, calibration, Keep Awake (also with the lid closed), and accessory battery levels and connection notices.
- Windows and display: the green button maximizes, ⌘M hides the app, F3 shows the desktop, Spaces keep their order, protection against quitting an app by accident, trackpad middle click and brightness keys for every display.
- Cleaning mode that locks the keyboard while you wipe it.
- Bluetooth walking pad control from the launcher.

### Downloads

- Download video, audio, transcripts and webpages from a copied link, optionally with aria2c.
- Distill: save links and transcribe media into a Markdown folder.
- Torrents from magnet links and torrent files, optionally over Wi-Fi and a plugged-in iPhone together.

### AI and agents

- A local agent bridge and command line tool, an MCP server and Notchcast tools in AI chat.
- Voice Ask, agent threads, OpenBot agents, an agent summary in the island, a fleet panel for T3 Code threads, and alerts when an agent waits for you. Agent requests ask for confirmation first.

### Two Macs

- Mac Link pairs two Macs on the local network: send the clipboard and files, open the other Mac over SSH, run its update, check its dialogs, and get notified when the link drops, with quick fixes.

### Backups, cleaning and updates

- Daily settings backups with a choice of which one to restore, and warnings when a backup fails or goes stale.
- Clean junk, history and AI data, analyze the disk, purge project build folders and optimize the system. Each one runs only when you click it.
- Check installed apps for updates, and run macOS maintenance after confirmation.

### Tweaks, privacy and startup

- Reversible Typing, Finder, Dock, Apple apps and iPhone backup tweaks, each applied after confirmation.
- Turn off Apple Intelligence features and Spotlight indexing, set privacy restrictions, Touch ID for `sudo`, manage startup items and dismiss disk-ejection alerts automatically.

### From Tinycast

Notchcast keeps upstream's features: app and command search, clipboard history, snippets, quicklinks, calculator with units and currencies, emoji picker, file search, menu bar search, window management, window layouts and rooms, notes, calendar and meeting join, camera, dictionary, Quick AI and AI chat with MCP servers, quick actions on selected text, custom commands, uninstall apps, global hotkeys with a Hyper key, and deeplinks. Upstream's docs are in [docs/features](/docs/features).

Hidden in Notchcast (the code stays): Raycast extensions, fallbacks, Apple Shortcuts, Tinycast backups, Raycast import and the donation window. The list and reasons: [hidden.md](/notchcast/docs/hidden.md).

<!-- features:end -->

## Requirements

- macOS 26 or later, Apple silicon (arm64 builds only).
- A notch is optional: on a display without one the island is a small pill at the top of the screen.
- Accessibility access for keys and window features; some features also ask for Screen Recording, Microphone, Calendars or Bluetooth when you turn them on.

## Install

1. Download `Notchcast-<version>.dmg` from [Releases](https://github.com/kaczordodgers/notchcast/releases). The newest non-pre-release follows upstream's latest release; the `snapshot` pre-releases are built from every green `main`.
2. Drag Notchcast to Applications.
3. Releases are signed with our own self-signed certificate and are not notarized, so remove the quarantine flag once:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Notchcast.app
   ```

4. Open Notchcast and grant Accessibility when asked.

Notchcast uses its own bundle id (`app.notchcast`) and URL scheme (`notchcast://`), so it can run beside Tinycast.

## Quickstart

1. Onboarding asks for the global shortcut that opens the launcher; change it later in **Settings → General → Global Shortcuts**.
2. Press it and type: an app, a command such as `Clipboard History`, or a sum such as `12*7`.
3. Open **Settings → Notchcast** and turn on the areas you want. The island appears at the top of the screen when **Island** is on.

Settings can also be mirrored to `~/.config/app.notchcast/settings.json` (**Settings → Notchcast → Backups → Settings File**); see [docs/features/settings-file.md](/docs/features/settings-file.md).

## Build from source

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone https://github.com/kaczordodgers/notchcast.git
cd notchcast
xcodegen generate
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build
```

The project, target and source folders keep upstream's `Tinycast` names so our commits rebase cleanly. Debug builds are `Notchcast Dev.app` (`app.notchcast.dev`). They sign ad-hoc, so headless Xcode builds them anywhere, but a local run loses its Accessibility grant on each rebuild; to keep it, pass `CODE_SIGN_IDENTITY="Tinycast Self-Signed"` after creating that identity once with [docs/signing.md §1](/docs/signing.md). Add `CODE_SIGNING_ALLOWED=NO` for a build-only check. Release signing is unchanged. More: [docs/development.md](/docs/development.md).

### Tests

```sh
./Scripts/run-tests.sh            # upstream's harnesses plus ours (no XCTest)
./Scripts/run-tests.sh calc-test  # one harness
./Scripts/lint.sh
```

Details: [docs/testing.md](/docs/testing.md).

### Project structure

```text
Tinycast/              app sources (upstream's name, kept for clean rebases)
  Features/<Name>/     one folder per feature; Notchcast's own features live beside upstream's
  Features/Notchcast/  shared fork code: feature switches, Settings tabs, launcher commands
Tests/                 runnable harnesses (Tests/nc-*-test.swift are ours)
Scripts/               upstream's build, test and lint scripts
docs/                  upstream's developer docs
notchcast/             fork tooling and docs: sync, landing, checks, notchcast/docs/
project.yml            XcodeGen input for Tinycast.xcodeproj
```

Contributing: [CONTRIBUTING.md](/.github/CONTRIBUTING.md). Security reports: [SECURITY.md](/.github/SECURITY.md).

## Credits

Notchcast is a fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, and it would not exist without it. This is a modified version, as the AGPL (section 5a) requires us to state: our changes are the commits on top of upstream `main`, and [notchcast/README.md](/notchcast/README.md) describes how they are kept and rebuilt. Bugs in Notchcast belong in [our issues](https://github.com/kaczordodgers/notchcast/issues), not upstream's.

Third-party material and its licences are listed in [NOTICE.md](/NOTICE.md).

## License

GNU Affero General Public License v3.0 or later, the same as Tinycast. See [LICENSE](/LICENSE). Tinycast is Copyright (C) 2026 Abue Ammar; Notchcast's changes are released under the same license.
