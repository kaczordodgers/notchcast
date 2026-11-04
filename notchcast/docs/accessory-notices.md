# Accessory notices

Reuses the island message surface for four-second connection and low-battery notices.
The default-on switch is independent of accessory battery Settings rows. Listening also
requires an explicit off/on switch action, persisted locally, and Bluetooth permission.
An undetermined permission is requested only by that action, never at launch.

Connection registration seeds already-connected devices; disconnect events re-arm them.
Battery readings reuse BatteryPeripheralService off-main every 30 seconds while listening.
Each peripheral reports once at 20% or below and re-arms at 25%, including across temporary
missing readings. Stopping clears the session state and cancels sampling.

The model maps device names to SF Symbols. The existing message surface only accepts text,
so displaying these symbols waits on design. No island layout is changed.

Validation: Tests/nc-AccessoryNotices-engine-test.swift uses a fake Bluetooth source.
