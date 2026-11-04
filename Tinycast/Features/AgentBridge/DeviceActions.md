# Device actions

`AgentDeviceActions.register(_:backend:in:)` adds device state and actions to an injected index.
The IDs double as machine-facing discovery titles. No launcher commands or views are registered.
The existing CLI uses `get device.treadmill`, `get device.katana` and
`run device.treadmill.start '{"speed":4,"minutes":30}'`. Dry runs validate without effects.
All device mutations are dangerous, including stop, pause and channel selection. The index defaults
to declining them. Never install an unconditional authorization callback in production.

The backend must validate its device generation and destination after every suspension, enforce
device-specific limits, and report failures. A tone ID references an existing local library entry;
it is never a path, raw MIDI packet or shell argument. Unknown IDs must fail before writing.

## Remaining wiring

AgentBridgeModule wires index authorization to AgentConsentPolicy and records execution attempts
through AgentAuditStore, with parameter values redacted. Dangerous actions are refused even with
persistent grants while island confirmation is unavailable. No confirmation UI is installed here.
The treadmill (#87) and Katana (#100) engines are not on main. Once integrated, their owning modules
must register AgentDeviceBackend adapters on the configured index and bind availability to connection
state and feature switches. Katana transactions must use the same per-transaction lock as the external katana.py CLI.
The external CLI retains raw reads/writes, offline preset tools, backups, restore and research;
this bridge never launches it or duplicates those tools. No production backend is installed here.

## Left for the look

Island confirmation and device action/state browsing remain unwired; no views are introduced.
