# Settings backup

The Notchcast Settings Backup switch defaults on and works independently of the island.
It writes one small binary property list per UTC day in the current app channel's Application
Support `fork-settings-backups` folder. A check runs on enable and hourly while enabled.
Existing daily files are preserved. Turning the switch off cancels subsequent checks.

This supplements upstream's backup engine; its hidden Settings pane remains untouched.
Only fork-local monitor thresholds, hover delay, charge percentage and keep-awake duration travel.
Feature switches, capability grants, credentials, upstream settings and store files are excluded.
Unknown keys are ignored on read and preserved in the current destination by the restore engine.
The entire archive is validated before returning a merged restore result. Wrong versions,
malformed values and archives larger than 1 MiB fail without changing preferences.

This engine-only increment does not expose import, export or restore controls. The restore engine
returns a validated merge to its caller; it does not apply it to running feature state.
No network or other application's data is involved. Automatic retention is not applied.

Run `./Scripts/run-tests.sh nc-SettingsBackup-engine-test` for the data-loss protection harness.
