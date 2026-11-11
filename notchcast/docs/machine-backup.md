# Machine backups

`MachineBackupCoordinator` exposes `runNow()`, `refreshSnapshots()`, `browse(snapshot:path:)`
and `restore(snapshot:path:target:)`. It is owned by `MachineBackupCoordinator.shared`, which registers itself.
Our features live in a Notchcast category in the Settings sidebar, one tab per module. Every switch has a working function, and its commands sit under it. Turning a switch off removes its commands. These are automatic settings rows;
neither switch depends on the island.

Call `configure(_:)` with local `MachineBackupConfiguration` before using the actions. No repository,
host, launchd label or credential-command defaults are compiled in. Configuration is supplied by the
caller and stays in memory. Switch persistence uses the existing fork-local preferences suite.
The inherited automatic switches default on, but starting the module never starts a backup,
contacts a repository or reads files. Missing configuration refuses every action.

Run-now only kickstarts the configured per-user launchd job, without restarting a running job.
The existing job owns backup concurrency and status; a successful kickstart means the request was
accepted, not that a backup completed. This feature never invokes `restic backup`, forget or prune.
An optional forced restore self-test flag is deferred.

Browsing uses restic JSON with the configured host filter and repository locks intact. The password
command is passed only to restic, which reads the credential itself. The runner uses an explicit
environment, disables restic's cache, discards standard error and limits standard output to 16 MiB.
Errors propagate as typed failures; caller UI owns their presentation. No tool output is logged.

Restores require a full snapshot ID, a literal path under the configured home and an explicit new
direct child of Downloads. System targets, traversal, wildcard selections, existing files,
directories and symlinks are refused. Downloads must resolve inside the canonical home. The runner
atomically reserves the destination with mode 0700 and asks restic to never overwrite. Failed or
cancelled restores leave partial output in that destination; the feature never removes it.
The caller should offer a unique `Restored-<date>` name and report the selected destination.

Operations are serialized. Switching a capability off, reconfiguring, stopping or caller cancellation
cancels the owned request and prevents stale results from publishing. Child processes get an interrupt
and then a kill after two seconds; a five-minute request deadline also cancels stalled tooling.
Cancelling kickstart does not cancel a launchd job that already accepted the request.

`Tests/nc-MachineBackup-actions-test.swift` uses fake tooling and disposable directories only.
No test starts a real backup, restores user data or connects to another machine.

Left for the look: snapshot browser, path selection, explicit destination picker and progress/error
presentation. No launcher commands, island pages, styling, helper verbs or new permissions are added.
