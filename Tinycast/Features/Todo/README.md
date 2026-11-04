# Reminder engine

`TodoReminderSchedule` is a pure snapshot. Supply the clock, calendar (including time zone), task
existence, due dates, completion set and snooze dates. `taskExists` is separate from the optional due
date so absolute reminders also work for tasks without a due date. Relative reminders without a due
date, negative offsets, completed tasks and deleted tasks have no scheduled entry. Rebuild on every
task or reminder edit. A relative reminder follows the latest due date including after an earlier occurrence fired.

All-day due dates represent a day in the supplied calendar. Their anchor is 09:00 local on that day;
minutes-before-due subtracts elapsed minutes, including across DST. Timed due dates and absolute
reminders are fixed instants. Tomorrow-morning snooze means 09:00 on the next calendar day, rather
than 24 elapsed hours later. The caller must preserve all-day civil dates when its time zone changes.

`TodoReminderState.check` returns one batch with `due` and `missed` entries, each oldest first, with
UUID as the tie-breaker. Entries exactly 24 hours late still fire; older entries are reported missed.
Both outcomes consume the reminder ID and fire-date pair. Persist the Codable state (`lastCheck` high-water mark and
`firedIDs`, containing ID/date pairs) and restore it before starting the timer. Past entries within
the cutoff are checked even when newly added or retimed behind `lastCheck`. Expired entries are
reported on first launch or when they cross the cutoff since the previous check. IDs stay stable;
each distinct fire date is a separate occurrence. Duplicate inputs keep the first occurrence.

Snoozes are per-reminder absolute dates that override the original time once. The caller owns and
persists them alongside reminders. To snooze a fired reminder, calculate the date with
`TodoReminder.Snooze.fireDate`, replace its snooze date, then call `TodoReminderTimer.rearm(id)`.
Changed due dates and moved absolute reminders automatically schedule another occurrence. Consumed
pairs older than the 24-hour cutoff are pruned; the check watermark prevents replaying expired entries.


`TodoReminderTimer` owns at most one non-repeating timer. `start()` checks launch catch-up immediately;
`check()` checks and rearms after an edit. Wake, system-clock and time-zone notifications rebuild the
schedule through its provider, which must read the current calendar and task data. Inject both
notification centres and the clock in tests. `stop()` cancels the timer and observers; queued
callbacks from an earlier timer or session are ignored. The owner must call `stop()` on teardown.

The state callback runs before delivery so the owner can checkpoint consumed IDs. The engine itself
does no file IO or presentation. Durable delivery across a crash requires the integrating owner to
coordinate that checkpoint with its delivery policy; this engine promises once per restored state.
No task store, island, notification permission or UserNotifications dependency is required.

`TodoAgentGateway.request(_:agent:calendar:staleAfterMinutes:makeID:)` is the consent boundary for
agent callers. The transport owner must supply the authenticated agent identity separately from
the request. Reads require `todo.read`; writes require `todo.write.<operation>` grants, including
`todo.write.releaseExpired`. Missing or revoked grants fail closed, even when confirmation allows.
The trusted owner supplies the write-confirmation policy and a synchronous local choice callback;
choices pass through `AgentConfirmationEngine`, with a 60-second deadline and allow-once semantics.
No transport or UI is started here. A future asynchronous presentation adapter must preserve grant
revalidation before mutation rather than retaining a precomputed command across suspension.

The required audit sink receives exactly one `TodoAgentGateway.Audit` per call, including failures.
It contains agent identity, action, task IDs and a typed result, with no task text or request payload.
The integrating owner owns durable audit storage; `AgentAuditEntry` currently redacts all parameters,
so passing task IDs through its parameters would lose them. The gateway does not change that engine.
List calls return the planner's view but never commit its expired-claim sweep; only write calls
commit cleanup. Main-actor serialization keeps planning and commit together without suspension.
## Launcher commands

Add Task from Clipboard parses one task with the quick-add parser, resolving existing projects,
sections and labels and parsing English or Polish dates. Complete Next Task uses the default Today
view ordering, including overdue tasks. Undo Last Task Change uses the store's persisted undo log.
Each action reports its result through command feedback and checks the Tasks switch before reading
the clipboard or accessing the store. The switch also refreshes launcher availability. Command deep
links use the command hook's standard consent gate.
