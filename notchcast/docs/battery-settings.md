# Battery and energy settings

`NotchcastSystemSettingsSection` owns the system monitor, fan, battery and energy rows in
Settings > Notchcast. These switches default off and work independently of the island.
Charge limits are 60, 70, 80 and 90%; keep-awake durations are 15–240 minutes.
Both options persist in the fork-local preferences suite.

Accessory Batteries defaults off and requires System Monitor. Its read-only Settings rows
sample IOKit peripheral readings on appearance and every 60 seconds while enabled and visible.
Charging appears only when the device reports it. No Bluetooth monitor or helper is started.

`BatteryModule` runs while any battery or energy switch is on, samples every 60 seconds,
and reevaluates immediately after
preference changes. Its injected runner owns helper commands and power assertions. Disabling
Keep Awake or quitting releases its assertions. The duration starts when Keep Awake is enabled
and resets if its duration changes; expiration leaves the switch on without renewing the hold.

Battery helper operations require installed helper version 3 or later and the corresponding
`battery-*` commands in the app contract. The installed version is refreshed at module start
and when the settings section appears. Older helpers show “Needs the Notchcast helper update”
and receive no battery commands. Until a watchdog is available, sailing and calibration drain
plans pause charging without disconnecting the adapter. Failed writes preserve the confirmed
state and show their error in Settings. Repeated evaluations skip confirmed unchanged root state.
Keep Awake uses no root helper.

The pure ownership journals persist intent before writes and confirmed values after success.
Each effect retains its own undo through failure, quit and relaunch. Repairs survive scheduling
changes and leave active features enabled. Each unchanged failed verb gets six automatic attempts,
with delays of 60, 120, 240, 480 and 960 seconds. Exhaustion remains persisted; a changed request
can start a new sequence. Exit 69 clears only the matching undo.
Native-limit cleanup restores the prior limit through its matching verb. An unrepresentable prior
limit leaves ownership and the current limit intact and reports an error. A different non-off
reading releases ownership without writing; an off reading retains ownership until undo succeeds.
Fans persist uncertain manual writes and failed automatic restores independently of the preference.
Silent failed restoration and shutdown preserve the selected preference.
An owned native limit is reissued once after a battery-to-adapter transition.
An existing macOS charge limit is read without claiming ownership. Calibration stops on relaunch
and turns its switch off on completion, recording the completion date.
Unsupported charging control also turns calibration off and labels it unsupported in Settings.

`Tests/nc-Battery-store-test.swift` uses fake readings, assertions and commands exclusively.
