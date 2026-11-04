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

`MachineSetupProfileExecutor` is intentionally unimplemented in production. Mac Setup tweak
application and the fork settings-backup dependency are not available on the branch base;
the root helper exposes no tweak verbs. No root verbs, shell execution or sudo paths are added.
Upstream Backup remains responsible for its five categories and capability exclusions.
The fake harness checks the boundary without touching user files or system settings.

Raw dotfiles, preference-domain serialization, secret redaction, file dialogs and first-run
import are deferred to that integration. This engine accepts structured safe values only;
it rejects suspect content rather than exporting a partly redacted shell file.
Allow-lists and user data must come from local configuration, never compiled personal paths.
No automatic Git backup or upload is implemented.

Source review: upstream Backup (AGPL-3.0), Damian Tools BackupFiles, BackupEngine and
SettingsTransfer (owner-authored), and the local mac-config payload layout. No source code
was copied from the reference applications and no private payload content is included.
