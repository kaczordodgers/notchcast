# Task island feed

Engine hook only: no island registration or visual surface exists yet. The default-off
`todoIsland` switch requires `.tasks` and belongs to the Tasks settings group. It stays in
`NotchcastFeature.unwired` (hidden, forced off) until the island page lands; unhiding is one line.
`NotchcastServices` injects its preference into `TodoModule`.
The module owns the feed while its store is open and the switch is enabled, exposes
`islandSnapshot` through Observation, and stops and releases the feed on switch-off,
store close or module stop. Its snapshot file is `Todo/island.json`; switching off deletes it.

`TodoIslandSnapshot(state:now:calendar:)` is a Codable, Sendable value. It uses
`TodoViews.today()` for overdue and today's incomplete tasks and its Upcoming query for tomorrow.
The three row arrays share a 16-row budget, in that order; `overflowCount` counts omitted rows.
Rows carry ID, title, optional timed due instant, priority (4 is highest) and optional project name.
Attention examines all candidates before truncation: overdue dates take precedence over due timed
tasks today. All-day tasks need no attention until the following day. No count accompanies attention.

`TodoIslandFeed(store:fileURL:calendar:now:presenter:)` borrows the active store.
The owner calls `start()` and `stop()`. Observation recomputes after a store mutation lands;
one nonrepeating timer targets the next calendar minute or day boundary. `refresh()` also permits
an owner to react to wake or clock changes. The injected calendar supplies the time zone.
Each refresh atomically replaces the JSON file; the parent directory must exist. A failed write
sets `failure` to `.snapshotWrite` while keeping the live snapshot available.

The later look still needs approved design, page and completion controls, quick add, a count-free
attention mark, hover/hotkey opening, and pin/refresh bindings.
