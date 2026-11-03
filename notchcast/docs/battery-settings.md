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

Battery helper operations require all six `battery-*` verbs in `RootContract.Command`. Until
then, battery rows show “Needs the Notchcast helper update” and issue no helper commands.
Adapter disconnection additionally requires a helper watchdog; sailing and calibration drain
plans stay unapplied until that capability is wired. Keep Awake uses no root helper.

`Tests/nc-Battery-store-test.swift` uses fake readings, assertions and commands exclusively.
