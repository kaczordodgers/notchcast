# Battery and energy settings

`NotchcastSystemSettingsSection` owns the system monitor, fan, battery and energy rows in
Settings > Notchcast. These switches default off and work independently of the island.
Charge limits are 50–100%, in steps of 5; keep-awake durations are 15–240 minutes.
Both options persist in the fork-local preferences suite.

`BatteryModule` runs while any battery or energy switch is on, samples every 60 seconds,
and reevaluates immediately after
preference changes. Its injected runner owns helper commands and power assertions. Disabling
Keep Awake or quitting releases its assertions. The duration starts when Keep Awake is enabled
and resets if its duration changes; expiration leaves the switch on without renewing the hold.

Battery helper operations require installed helper version 3 or later and the corresponding
`battery-*` commands in the app contract. The installed version is refreshed at module start
and when the settings section appears. Older helpers show “Needs the Notchcast helper update”
and receive no battery commands. Until a watchdog is available, sailing and calibration drain
plans pause charging without disconnecting the adapter. Failed writes preserve the last applied
state and show their error in Settings. Repeated evaluations skip unchanged root state.
Keep Awake uses no root helper.

`Tests/nc-Battery-store-test.swift` uses fake readings, assertions and commands exclusively.
