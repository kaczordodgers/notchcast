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

Restore Settings Backup validates the newest numeric `settings-<day>.plist` before asking for
confirmation, then applies only archived keys through the running preferences setters. A bad newest
file is refused without falling back. Unsupported in-range charge, awake-duration and hover-delay
choices normalize to 80 percent, 60 minutes and 0.3 seconds. Missing backups show a notice.
Open Settings Backup Folder creates and opens the folder. Both commands work with the switch off.
No network or other application's data is involved. Automatic retention is not applied.

Run `./Scripts/run-tests.sh nc-SettingsBackup-engine-test` for the data-loss protection harness.
Run `./Scripts/run-tests.sh nc-SettingsBackup-restore-test` for real preference restore checks.
