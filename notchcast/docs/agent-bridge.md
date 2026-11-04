# Agent bridge

`NotchcastCore.agents.index` owns action registration and read-only state providers. Modules register
an `AgentActionIndex.Entry` or `StateProvider` once, with a live availability closure. Registration
rejects duplicate IDs. Parameters use a closed object schema with string, boolean, number and integer
properties, required fields, numeric bounds, allowed values and minimum string lengths. Discovery exposes the same JSON Schema used to
validate execution. Upstream built-ins come directly from their existing catalogues and dispatch
through the existing hotkey or system-action coordinator; success means `dispatched`.

The Agent access and Command line tool switches are independent of the island. Both follow the
fork's default-on switch policy. Turning Agent access off invalidates pending approvals and stops
the socket. Turning Command line tool off stops the socket alone. Preferences stay in the fork-local,
bundle-specific store. No agent authorization is persisted or imported.

## Protocol

Settings can link the bundled `Contents/Helpers/notchcast` tool into `~/.local/bin`. Installation never
replaces an unrelated file or symlink. The helper resolves its enclosing app's bundle ID, so Debug and
Release use separate endpoints under `~/Library/Application Support/<bundle-id>/agent/socket`.
The containing directory is `0700`, the socket is `0600`, and both peers verify the effective UID.
A file lock protects the endpoint against another listener; only an owned stale socket is removed.
An overlong Unix socket path fails explicitly rather than choosing a shared fallback location.

One JSON request line produces one JSON reply line, then the connection closes. Frames are capped at
1 MiB. There are at most eight active clients, bounded read/write/handler deadlines, no idle polling,
and cancellation on disconnect, timeout or stop. Socket IO runs outside the main actor.

```
notchcast list --json
notchcast get notchcast.features --json
notchcast run system-action:set-volume '{"level":0.5}' --dry-run --json
notchcast status --json
notchcast audit --json
```

Wire requests contain `verb`, optional `id`, `parameters` (default `{}`) and `dryRun` (default false).
Replies contain `code` and `result`. The CLI prints compact JSON with `--json`, pretty JSON otherwise.
Exit codes are 0 success, 1 failed/unavailable, 2 invalid request, 3 not running and 5 declined.
Dry runs validate schema and availability without asking for consent or running effects.

## Consent and audit

The bridge uses AgentConsentPolicy and the bundle-isolated AgentGrantStore. The socket identifies
clients only as local-cli; without authenticated per-agent identity, requests needing a new approval
fail closed. Dangerous actions remain refused while island confirmation is unavailable.
AgentAuditStore records completed execution requests with redacted parameters. The audit verb returns
persisted entries; malformed JSONL records are skipped and counted without hiding valid records.

## Left for the look

Island action/state browsing, confirmation cards and the audit list remain on hold. All state and
action APIs are exposed without new island views. Command/hotkey registration waits for its hook.

## Device actions

`AgentDeviceActions.register(_:backend:in:)` adds device state and actions to an injected index.
The IDs double as machine-facing discovery titles. No launcher commands or views are registered.
The existing CLI uses `get device.treadmill`, `get device.katana` and
`run device.treadmill.start '{"speed":4,"minutes":30}'`. Dry runs validate without effects.
All device mutations are dangerous, including stop, pause and channel selection. The index defaults
to declining them. Never install an unconditional authorization callback in production.

The backend must validate its device generation and destination after every suspension, enforce
device-specific limits, and report failures. A tone ID references an existing local library entry;
it is never a path, raw MIDI packet or shell argument. Unknown IDs must fail before writing.

### Remaining wiring

AgentBridgeModule wires index authorization to AgentConsentPolicy and records execution attempts
through AgentAuditStore, with parameter values redacted. Dangerous actions are refused even with
persistent grants while island confirmation is unavailable. No confirmation UI is installed here.
The treadmill (#87) and Katana (#100) engines are not on main. Once integrated, their owning modules
must register AgentDeviceBackend adapters on the configured index and bind availability to connection
state and feature switches. Katana transactions must use the same per-transaction lock as the external katana.py CLI.
The external CLI retains raw reads/writes, offline preset tools, backups, restore and research;
this bridge never launches it or duplicates those tools. No production backend is installed here.

### Left for the look

Island confirmation and device action/state browsing remain unwired; no views are introduced.
