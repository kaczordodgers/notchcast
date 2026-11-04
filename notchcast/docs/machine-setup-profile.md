# Machine setup profile engine

The fork-only engine models a versioned `.notchcast` payload and a deterministic import plan.
Its plain Settings switch appears under System, independently of the island.

## Invariants

- Format and application versions must match exactly.
- Only locally supplied file/key, module/key and tweak ID allow-lists are accepted.
- Structured settings reject sensitive key names, path values and high-entropy strings.
- Planning performs no writes. Applying requires an enabled feature and explicit consent.
- The executor validates the upstream backup and every destination before any write.
- A real executor must reject symlink destinations and use existing fork mutation paths.

## Integration boundary

The Machine Setup Profile launcher command chooses a JSON profile and previews it before
using the existing destructive confirmation dialog. Turning off its switch prevents application.
The production executor currently accepts only empty backup, file and module payloads and the
fixed tweak IDs `dock.autohide` and `system.firewall`. Dock autohide is set to true using
`/usr/bin/defaults` with an argument array; a missing key is treated as false. A successful write
runs the fixed `/usr/bin/killall Dock` command before verification; restart failure fails the step.
Already satisfied steps are skipped. Firewall is
reported as needing a helper and skipped. No root verbs, shell execution or sudo paths are added.
Each process has a five-second deadline, followed by termination and forced termination if needed.
The first failure stops the run and reports remaining steps as not run. Process output is never
included in reports. Cancellation is deferred; an operation already started finishes within its
process deadlines even if the feature is subsequently disabled.
Upstream Backup remains responsible for its five categories and capability exclusions.
The fake harness checks the boundary without touching user files or system settings.

Raw dotfiles, preference-domain serialization, secret redaction and first-run
import are deferred to that integration. This engine accepts structured safe values only;
it rejects suspect content rather than exporting a partly redacted shell file.
Allow-lists and user data must come from local configuration, never compiled personal paths.
No automatic Git backup or upload is implemented.

For this executor, a JSON profile has `format: 1`, `appVersion` matching the running app's
short version, `backup: ""`, `files: {}`, `modules: {}` and, for example,
`tweaks: ["dock.autohide", "system.firewall"]`. Enable Machine Setup Profile in Settings,
then run Machine Setup Profile from the launcher and select that JSON file. Cancel leaves
the preview unapplied. The command never accepts executable paths or arguments from the file.

Source review: upstream Backup (AGPL-3.0), Damian Tools BackupFiles, BackupEngine and
SettingsTransfer (owner-authored), and the local mac-config payload layout. No source code
was copied from the reference applications and no private payload content is included.
