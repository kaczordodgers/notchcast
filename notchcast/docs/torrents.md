# Torrents

Our features live in a Notchcast category in the Settings sidebar, one tab per module. Every switch has a working function, and its commands sit under it. Turning a switch off removes its commands. Torrents and using a connected iPhone default on;
sharing until ratio 1.0 defaults off. Neither downloading nor its settings require the island.
The iPhone and sharing switches are disabled while Torrents is off. Preferences stay in the
bundle-scoped Notchcast store, outside upstream settings mirrors and backups.

The section shows Checking… during lookup, then the detected aria2c path or its missing status.
Each job shows its name, progress, state and any failure, with Cancel, Try Again and Show in Finder.
Try Again replaces its row; terminal rows have Dismiss. Files go to Downloads and completed files
receive the Notchcast quarantine attribute. Jobs are retained in memory for the current app session.
RPC errors affect one job; transport failures are retried while the child lives. The no-peer deadline
uses a suspending clock so time asleep does not consume its ten minutes.

`TorrentModule` owns the manager and interface monitor. Its entry requires only `.torrents`.
Turning the switch off immediately rejects inputs and cancels job state, then asynchronously stops
the child. Opens received after re-enabling during shutdown wait for that shutdown to finish.

`TorrentAria2Session` owns one `ProcessRunner.Running` handle. Stop signals only the aria2 PID with INT, TERM after one second and KILL after two seconds, then awaits reaping. Termination and session release kill it immediately. Listener ownership and the authenticated RPC handshake still gate startup.

The existing queued `AppCore.handleOpenURL` path forwards magnet links and local `.torrent` file
URLs to the module. Unsupported URLs return unhandled; disabled torrent inputs show a settings HUD.
The Info.plist
declares the magnet scheme and imports `org.bittorrent.torrent` as an alternate viewer; the module
never changes the user's default application.

Interface discovery runs on demand at session start and to label each new job. With the iPhone switch on,
`NetMergePolicy` injects `--multiple-interface` only when both Wi-Fi and iPhone USB have IPv4.
Discovery failure permits ordinary downloading. A running child keeps its original interface choice,
including jobs added to that child; disconnecting a cable never restarts it. Once idle, the next child
reads interfaces and preferences again. New jobs show Wi-Fi + iPhone only when both interfaces
selected by that child are still present with IPv4. A newly connected interface cannot join an
existing child; it becomes eligible after that child idles. Existing rows retain their admission label.

Proof: `nc-Torrents-module-test`, `nc-Torrents-engine-test`, `nc-NetMerge-policy-test` and
`notchcast-core-test`. The module harness covers defaults, island independence, disabled inputs,
magnet and file routing, sharing, session policy injection, missing interfaces, discovery failure,
and off/on input buffering during shutdown.
