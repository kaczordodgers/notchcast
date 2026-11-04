# Remote dialog alerts

Remote Dialog Alerts defaults off in the System section beside the remote Mac switches.
Mac Link and this switch must both be enabled. The module samples on-screen window metadata
every 15 seconds; stopping cancels its task and clears the local detection state.

Only visible windows above layer zero owned by UserNotificationCenter, CoreServicesUIAgent,
SecurityAgent or universalAccessAuthWarn qualify. Window titles are never read. Process and
window identifiers distinguish dialogs locally; only an occurrence UUID and Mac name travel
in the authenticated MachLink `dialog-shown` message. Each observed appearance sends once.
Failed sends are best effort; a dialog that disappears and returns creates a new occurrence.

The listener route installed by NotchcastCore delivers to the module. The receiver remembers
the most recent 256 occurrence UUIDs and posts through the existing remote status-notice seam,
which respects Status Messages. No new island surface or action is added.

The blocked-dialog harness injects synthetic window lists and an in-memory link. It verifies
all four owners, layer filtering, de-duplication, default-off behavior, stop and status gating.
Live process-name coverage and delivery between Macs remain morning verification work.
