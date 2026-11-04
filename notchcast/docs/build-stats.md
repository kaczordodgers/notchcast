# Build statistics

The plain Notchcast Settings section has an opt-in switch and a local snapshot path.
The path is empty by default and persists only in the channel's fork preferences.
No collector or private snapshot ships with the app.

The row loads only while shown and enabled. Its SwiftUI task owns cancellation;
path changes cancel the previous request and results are checked before display.
The loader reads a regular file off the main actor, bounded to the schema byte limit,
and validates it with `BuildStatsSnapshot.decode` before aggregation. Missing,
unreadable, oversized, invalid and overflowing totals produce typed failures.

The read model exposes token totals by model and by effort, ascending timeline
entries, newest-first changelog entries, quality metrics and an entry count.
Snapshot strings remain untrusted data: future views must render them verbatim.
There is no polling, module registration, island integration or visual pane yet.

Run `./Scripts/run-tests.sh notchcast-build-stats-loader-test` for fixture and error coverage.
