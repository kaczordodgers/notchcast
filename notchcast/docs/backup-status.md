# Backup status

The Backup Status switch defaults off and starts a read-only module independently of the island
switch. Notices use the existing island status-message API; its presentation preferences still apply.
There is no backup page or transport to another Mac.

The module reads the backup job's version 1 JSON at
the user-configured status file path (empty by default). A directory DispatchSource handles
atomic replacement, deletion and recreation; when the directory is absent it watches the nearest
existing ancestor until the directory appears. Reads run off the main actor and obsolete reads are
discarded. Remote Time Machine information comes only from the embedded JSON.

A two-hour deadline applies to the last successful backup, last attempt and embedded remote backup.
One timer targets the next deadline. Newly appearing health issues post one generic localized notice;
unchanged issues stay quiet until they recover. Missing or malformed data is an unavailable issue.
Stopping cancels monitoring, reads and the deadline and clears notice history.

`Tests/notchcast-mach-backup-status-test.swift` covers parsing, injected file-change callbacks,
deadline notices, duplicate suppression and switch-driven teardown using synthetic data only.
