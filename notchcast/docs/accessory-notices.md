# Accessory notices

Reuses the island message surface for four-second connection and low-battery notices.
The default-off switch is independent of accessory battery Settings rows. Turning it on
is the opt-in: the module starts, requests undetermined Bluetooth permission and listens
once authorized. Turning it off stops listening. First launch never requests Bluetooth access.

Connection registration seeds already-connected devices; disconnect events re-arm them.
Battery readings reuse BatteryPeripheralService off-main every 30 seconds while listening.
Each peripheral reports once at 20% or below and re-arms at 25%, including across temporary
missing readings. Stopping clears the session state and cancels sampling.

The existing message surface only accepts text; accessory symbols wait on design.
No island layout is changed.

Validation: Tests/nc-AccessoryNotices-engine-test.swift uses a fake Bluetooth source.
