# Torrents

Settings > Notchcast has one Torrents section. Torrents and using a connected iPhone default on;
sharing until ratio 1.0 defaults off. Neither downloading nor its settings require the island.
The iPhone and sharing switches are disabled while Torrents is off. Preferences stay in the
bundle-scoped Notchcast store, outside upstream settings mirrors and backups.

The section shows the detected aria2c path, or its missing status, with the Homebrew install command.
Each job shows its name, progress, state and any failure, with Cancel, Try Again and Show in Finder.
Files go to Downloads. Jobs are retained in memory for the current app session.

`TorrentModule` owns the manager and interface monitor. Its entry requires only `.torrents`.
Turning the switch off immediately rejects inputs and cancels job state, then asynchronously stops
the child. Opens received after re-enabling during shutdown wait for that shutdown to finish.

The existing queued `AppCore.handleOpenURL` path forwards magnet links and local `.torrent` file
URLs to the module. Unsupported URLs and all inputs while disabled return unhandled. The Info.plist
declares the magnet scheme and imports `org.bittorrent.torrent` as an alternate viewer; the module
never changes the user's default application.

Interface discovery runs on demand when a new aria2 session starts. With the iPhone switch on,
`NetMergePolicy` injects `--multiple-interface` only when both Wi-Fi and iPhone USB have IPv4.
Discovery failure permits ordinary downloading. A running child keeps its original interface choice,
including jobs added to that child; disconnecting a cable never restarts it. Once idle, the next child
reads interfaces and preferences again. Each job retains whether its session used Wi-Fi + iPhone.

Proof: `nc-Torrents-module-test`, `nc-Torrents-engine-test`, `nc-NetMerge-policy-test` and
`notchcast-core-test`. The module harness covers defaults, island independence, disabled inputs,
magnet and file routing, sharing, session policy injection, missing interfaces, discovery failure,
and off/on input buffering during shutdown.
