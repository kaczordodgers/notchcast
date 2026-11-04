# Capture and dictation settings

Settings > Notchcast groups capture and dictation controls in one stock Settings section.
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

Screen Recording appears in the existing Notchcast permissions section while Screenshots or recording is on.
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

## Verification

AI cleanup is off by default and independent of Island. Its switch installs the engine's final
transcript stage; switching off removes it so raw transcripts flow through. Endpoint, effort,
prompt addition and multiline vocabulary use the engine's fork-local settings store. Each vocabulary
line contains a spelling followed by optional misheard forms separated by `|`. The API key is saved
explicitly with Save or Return through the engine's bundle-scoped Keychain store. Neither credentials
nor capability flags enter settings.json or upstream backups. No launcher command is added.

`./Scripts/run-tests.sh nc-ColorPicker-lifecycle-test` checks disabled sampling, switch teardown,
re-enabling, format persistence and Island independence with injected sampling and clipboard effects.
`./Scripts/run-tests.sh nc-CaptureScreenshot-lifecycle-test` checks switch teardown, caller and destination
cancellation, folder persistence and unchanged Quartz rectangles with an injected capture effect.
Neither harness samples the screen, prompts for permissions or touches the user's clipboard or folders.

`./Scripts/run-tests.sh nc-CaptureRecording-engine-test` checks countdown, switch lifecycle, cancellation
at suspended boundaries, pause timing, naming collisions and defaults in private fixtures. Synthetic
pixel and PCM buffers exercise the shipped H.264/AAC writer, including its still-frame tail.
Cancellation waits for native finalization to begin, then requires finish to return within two seconds.
