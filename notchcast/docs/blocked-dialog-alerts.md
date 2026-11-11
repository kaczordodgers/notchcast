# Other Mac dialog alerts

The plain Notchcast switch enables the `dialogs` Mac Link method. Both Macs must
enable Mac Link and dialog alerts. The receiving Mac also needs the island and
status messages enabled. `BlockedDialogModule.shared?.check()` performs one
on-demand request; there is no timer or automatic retry.

The detector reads visible window metadata and recognizes four system owners:
UserNotificationCenter, universalAccessAuthWarn, SecurityAgent and
CoreServicesUIAgent. Only positive-layer, nonempty windows qualify. This is a
heuristic, not proof that automation is blocked. App-owned TCC prompts are not
classified because metadata alone does not identify them reliably.

No window titles, dialog text or screenshots are read, logged or persisted.
Candidate metadata and dedupe state live in memory. Alerts use the existing
island status message API, with a 60-second cooldown. Disappearing windows are
eligible again after the cooldown; stopping the module clears its state.

The remote-screen action, CLI command and automation-failure trigger are deferred
to their integration work. No new alert UI is introduced here.

Run `./Scripts/run-tests.sh notchcast-blocked-dialog-test`. The harness injects a
fake Mac Link transport and never contacts another Mac.
