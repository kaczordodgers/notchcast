# Capture and dictation settings

Our features live in a Notchcast category in the Settings sidebar, one tab per module. Every switch has a working function, and its commands sit under it. Turning a switch off removes its commands.
Its switches use `NotchcastPreferences` and `NotchcastModuleController`, independently of the Island
switch. Preferences stay in the bundle-scoped `.notchcast` defaults suite, outside upstream settings
exports and backups. Switches follow the existing Notchcast default of on.

## Color picker

`NotchcastCore.colorPicker` owns `ColorPickerModule` and its native `ColorPickerService`.
The switch enables on-demand sampling; disabling invalidates pending sampler output. Enabling never
opens the sampler. The format picker persists the engine's six formats, with uppercase hex as default.
Pick Color (`command:nc-pick-color`) invokes `ColorPickerModule.pick(completion:)` from the launcher.

## Screenshots

`NotchcastCore.screenshot` owns `ScreenshotModule`. The switch enables on-demand capture; disabling
cancels its current operation. Changing the output destination or folder also cancels a pending capture,
and caller cancellation propagates to the engine. No capture or permission prompt runs at startup.

The destination defaults to Clipboard. File and Clipboard and file enable a folder chooser, with Desktop
as the engine's default folder. `ScreenshotModule.capture(_:)` accepts the engine's rectangle, window and
display requests. Rectangle coordinates stay in global Quartz points with a top-left origin.
Capture Screen (`command:nc-screenshot-display`) captures the display under the pointer to the selected
destination. Both commands disappear when their switch is off and work with Island off.

Screen Recording appears in Capture’s Permissions section while Screenshots or recording is on.
Its status is read without prompting; Open goes directly to macOS Privacy & Security because upstream's
Permissions pane has no Screen Recording row. The engine asks for access only when capture is invoked.

## Recording

`NotchcastCore.recording` owns `RecordingModule`. Enabling prepares the on-demand engine without
capturing or requesting access. Disabling cancels countdown, startup, recording or finalization and
discards its temporary file. It works independently of Island and adds no launcher command or page.

Call `record(.area(selection.rect))`, `record(.window(id))` or `record(.display(id))` to start after a
three-second countdown. Area rectangles use CaptureArea's global Quartz points. `phase` reports the
countdown and recording state; `setPaused(_:)` pauses or resumes, `finish()` saves and returns the MP4
URL, and `cancel()` discards. Await `waitUntilIdle()` after cancellation before starting another take.
Errors throw from start/finish; unexpected stream and cleanup errors also appear in `lastError`.

The writer uses H.264 with AAC system audio, no microphone, the pointer visible and clicks hidden.
Pauses remove time from both tracks. Frame rate is 30 or 60, defaulting to 60; the folder defaults to
the current user's Downloads directory. Both preferences use the Notchcast defaults suite. Changes
apply to the next take. Stop publishes `Recording YYYY-MM-DD at HH.MM.SS.mp4`, adding a suffix for
collisions; it never replaces an existing file. The temporary workspace stays in the selected folder.
`RecordingSource` and `RecordingWriting` inject capture and encoding for isolated harnesses.
## Globe dictation

The Globe Dictation switch owns `DictationTriggerManager` through `DictationTriggerModule` on
the shared event-tap hub. It works with Island off and, while upstream Dictation is enabled,
reserves Globe from upstream modifier bindings
without deleting them, and pauses during shortcut recording. Disabling stops the manager and releases
the reservation. Accessibility is listed in the existing permissions section.

The trigger uses the upstream dictation coordinator's consent and model checks. Tap Globe to start,
tap again to finish, or hold for at least 350 ms and release to finish. Return and keypad Enter finish
the recording, including its 200 ms audio tail; Escape with Globe held discards it, panel focus or not.
Capture begins on a solo tap's release or after the hold threshold, so Fn chords have no
capture effects. Other input cancels a provisional press and finishes a confirmed hold. Disabling
the switch finishes any recording it started, preserving the text. This switch adds no launcher command.

`./Scripts/run-tests.sh nc-DictationTrigger-lifecycle-test` checks lifecycle, shortcut-recording pause,
Globe reservation and Island independence with injected effects and isolated test preferences.

## Dictation owner

`DictationFamily` (`Features/Notchcast/Dictation/`, in the kernel so features depend on it; only its `+Live` file reads the cleanup and English features) is the one fork owner of dictation session state. It holds the upstream coordinator, which the Globe trigger and Dictate in English bind at start, and answers availability, recording and start, finish and cancel for both. It also holds the cleanup and history switches, installs the coordinator's transcript stages from them, and routes every finished transcript to the history sink once. The island HUD is not routed through it: upstream's panel hands it the display state. Cleanup and English both run through one live-settings read, and English keeps its own prompt and timeout. Dictate in English keeps swallowing a held grave key's repeats until key-up, even after fn is released. `./Scripts/run-tests.sh notchcast-dictation-family-test` checks session reads, stage installation, the history gate and English routing.

## Verification

Dictation history settings show the latest 100 saved transcripts, newest first, with two-line text,
local date and time, and a Copy button. Clear History uses the app's destructive confirmation and
leaves an empty state after deletion. Saved content and the 90-day retention policy are unchanged.
`./Scripts/run-tests.sh nc-DictationHistory-list-test` checks ordering, the cap and deletion in a
temporary store. Gallery pages `settings-dictation-history-{populated,empty}-{dark,light}` use fixtures.

AI cleanup is off by default and independent of Island. Its switch installs the engine's final
transcript stage; switching off removes it so raw transcripts flow through. Endpoint, effort,
prompt addition and multiline vocabulary use the engine's fork-local settings store. Each vocabulary
line contains a spelling followed by optional misheard forms separated by `|`. The API key is saved
explicitly with Save or Return through the engine's bundle-scoped Keychain store. Neither credentials
nor capability flags enter settings.json or upstream backups. No launcher command is added.
Capture Text (`command:nc-screen-text`) selects an area and copies recognized text or barcode content.
Remove line breaks persists in the fork defaults suite and cancels pending recognition when changed.
Scrolling Capture (`command:nc-scrolling-capture`) selects a Quartz area and collects scrolling frames.
Run the command again to stop and copy the stitched PNG; reaching 20,000 pixels copies automatically
and presents a HUD notice. Both switches are independent of Island and require Screen Recording only
when invoked. Disabling either cancels selection and pending output. Capture commands report distinct
permission, unavailable-area, recognition and clipboard failures through the existing HUD.

`./Scripts/run-tests.sh notchcast-capture-wiring-test` checks the new switch lifecycle, permission
gating, OCR option persistence, command refresh for every switch and Island independence with private
defaults and denied permission probes. `notchcast-commands-test` covers command dispatch and filtering.

`./Scripts/run-tests.sh notchcast-capture-errors-test` checks screenshot permission, clipboard,
capture and file-write messages, plus the colour command's failed-copy HUD and successful-copy silence.

`./Scripts/run-tests.sh nc-ColorPicker-lifecycle-test` checks disabled sampling, switch teardown,
re-enabling, format persistence and Island independence with injected sampling and clipboard effects.
`./Scripts/run-tests.sh nc-CaptureScreenshot-lifecycle-test` checks switch teardown, caller and destination
cancellation, folder persistence and unchanged Quartz rectangles with an injected capture effect.
Neither harness samples the screen, prompts for permissions or touches the user's clipboard or folders.

`./Scripts/run-tests.sh nc-CaptureRecording-engine-test` checks countdown, switch lifecycle, cancellation
at suspended boundaries, pause timing, naming collisions and defaults in private fixtures. Synthetic
pixel and PCM buffers exercise the shipped H.264/AAC writer, including its still-frame tail.
Cancellation waits for native finalization to begin, then requires finish to return within two seconds.
