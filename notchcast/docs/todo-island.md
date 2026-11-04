# Task island feed

Engine hook only: no island registration or visual surface exists yet.

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

`complete(_:) throws` issues store commands. Recognized recurrence strings advance through
`TodoRecurrence`, leave the parent incomplete and reset descendants in one undoable batch.
Unsupported recurrence throws `.unsupportedRecurrence` without modifying the task.
`TodoIslandPresenting.update(_:)` is the typed presentation seam; nothing implements it here.

The later look still needs approved design, page and completion controls, quick add, a count-free
attention mark, hover/hotkey opening, pin/refresh bindings, and module ownership/switch wiring.
