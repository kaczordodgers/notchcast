# Home engine

Engine only, no view binding. Home has no separate preference. The existing page remains untouched
for the design pass; the model prescribes no columns, section headers or geometry.

`IslandHomeModel.entries(live:now:)` accepts value snapshots and an injected clock. The reading order
is failure, attention, active work, playback (including paused tracks), status messages, then results.
Within live states, higher priority wins, followed by newest timestamp and source/key lexical order.
The live limit is 20; recent results show three and retain 50, newest first. Empty input returns empty.

IDs identify a producer and its stable item key. Newest values win duplicate IDs; equal timestamps
use the last supplied value. Live items suppress matching history even when outside the visible cap.
Explicit expiry is exclusive: an item disappears at its expiry instant. Results otherwise survive
until cleared or evicted. Timer end dates are readouts, not expiry: the activity owner must finish
the timer. Progress is clamped and nonfinite values discarded; invalid IDs, titles and dates are dropped.

`IslandHomeActivityAdapter` reads activities and the current status message synchronously from an
injected center. It retains no callbacks or singleton. Message dwell and activity lifetime remain
owned by that center. Pass its output with other producer snapshots to the model.

Downloads, speed tests, walks and Disk supply stable source/key entries for active work, failures
and completed results; call `retain` for completed results. Playback supplies a `.playing` snapshot.
Time Machine supplies `.attention` with a producer-owned snooze and expiry. These are value inputs,
not new polling services; producer wiring and backup probing are deferred alongside view binding.

The pure model supports clear, clear all and LIFO undo. Call `close()` when the island closes to
forget undo. Its Codable history is exposed for a future bundle-scoped persistence owner; this
change adds no disk writes. Restore via `init(history:)` to reapply validation, dedupe and limits.

Validation: `./Scripts/run-tests.sh notchcast-island-home-test` uses fake producer values and an injected
activity center. No upstream hooks or generated files are needed.
