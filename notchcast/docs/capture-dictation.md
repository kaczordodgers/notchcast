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

Screen Recording appears in the existing Notchcast permissions section while Screenshots is on.
Its status is read without prompting; Open goes directly to macOS Privacy & Security because upstream's
Permissions pane has no Screen Recording row. The engine asks for access only when capture is invoked.

## Globe dictation

The Globe Dictation switch owns `DictationTriggerManager` through `DictationTriggerModule` on
the shared event-tap hub. It works with Island off and, while upstream Dictation is enabled,
reserves Globe from upstream modifier bindings
without deleting them, and pauses during shortcut recording. Disabling stops the manager and releases
the reservation. Accessibility is listed in the existing permissions section.

The trigger uses the upstream dictation coordinator's consent and model checks. Tap Globe to start,
tap again to finish, or hold for at least 350 ms and release to finish. Return and Escape finish the
recording, including its 200 ms audio tail; Escape during transcription keeps the result pending for
insertion. Capture begins on a solo tap's release or after the hold threshold, so Fn chords have no
capture effects. Other input cancels a provisional press and finishes a confirmed hold. Disabling
the switch finishes any recording it started, preserving the text. This switch adds no launcher command.

`./Scripts/run-tests.sh nc-DictationTrigger-lifecycle-test` checks lifecycle, shortcut-recording pause,
Globe reservation and Island independence with injected effects and isolated test preferences.

## Verification

`./Scripts/run-tests.sh nc-ColorPicker-lifecycle-test` checks disabled sampling, switch teardown,
re-enabling, format persistence and Island independence with injected sampling and clipboard effects.
`./Scripts/run-tests.sh nc-CaptureScreenshot-lifecycle-test` checks switch teardown, caller and destination
cancellation, folder persistence and unchanged Quartz rectangles with an injected capture effect.
Neither harness samples the screen, prompts for permissions or touches the user's clipboard or folders.
