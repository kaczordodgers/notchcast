# Reminder engine

`TodoReminderSchedule` is a pure snapshot. Supply the clock, calendar (including time zone), task
existence, due dates, completion set and snooze dates. `taskExists` is separate from the optional due
date so absolute reminders also work for tasks without a due date. Relative reminders without a due
date, negative offsets, completed tasks and deleted tasks have no scheduled entry. Rebuild on every
task or reminder edit. A relative reminder follows the latest due date until it has fired.

All-day due dates represent a day in the supplied calendar. Their anchor is 09:00 local on that day;
minutes-before-due subtracts elapsed minutes, including across DST. Timed due dates and absolute
reminders are fixed instants. Tomorrow-morning snooze means 09:00 on the next calendar day, rather
than 24 elapsed hours later. The caller must preserve all-day civil dates when its time zone changes.

`TodoReminderState.check` returns one batch with `due` and `missed` entries, each oldest first, with
UUID as the tie-breaker. Entries exactly 24 hours late still fire; older entries are reported missed.
Both outcomes consume the reminder ID. Persist the Codable state (`lastCheck` high-water mark and
`firedIDs`) and restore it before starting the timer. All unconsumed past entries are checked,
including on first launch or when a reminder is newly added or retimed behind `lastCheck`. Thus a
backward clock jump cannot hide a new reminder or replay an old one. IDs must be unique and stable;
reusing one means the same one-shot reminder. Duplicate inputs keep the first occurrence.

Snoozes are per-reminder absolute dates that override the original time once. The caller owns and
persists them alongside reminders. To snooze a fired reminder, calculate the date with
`TodoReminder.Snooze.fireDate`, replace its snooze date, then call `TodoReminderTimer.rearm(id)`.
When the snooze fires, the same ID is consumed again. Removing a consumed snooze does not restore
the original fire. Only explicit rearming can reuse a consumed ID; changing a task due date cannot.
Do not prune consumed IDs while their reminders may still be restored.

`TodoReminderTimer` owns at most one non-repeating timer. `start()` checks launch catch-up immediately;
`check()` checks and rearms after an edit. Wake, system-clock and time-zone notifications rebuild the
schedule through its provider, which must read the current calendar and task data. Inject both
notification centres and the clock in tests. `stop()` cancels the timer and observers; queued
callbacks from an earlier timer or session are ignored. The owner must call `stop()` on teardown.

The state callback runs before delivery so the owner can checkpoint consumed IDs. The engine itself
does no file IO or presentation. Durable delivery across a crash requires the integrating owner to
coordinate that checkpoint with its delivery policy; this engine promises once per restored state.
No task store, island, notification permission or UserNotifications dependency is required.
