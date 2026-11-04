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

This base has neither device engine nor AgentConsentPolicy. Once their branches are integrated,
the owning modules must register backends and connect index authorization to the island confirmation
policy. Katana transactions must use the same per-transaction lock as the external katana.py CLI.
The external CLI retains raw reads/writes, offline preset tools, backups, restore and research;
this bridge never launches it or duplicates those tools. No production backend is installed here.

Merging current main into the agent branch conflicts in core, settings, the core harness and strings;
that dependency update belongs to the agent branch owner before this is a landing candidate.

## Left for the look

Island confirmation and device action/state browsing remain unwired; no views are introduced.
