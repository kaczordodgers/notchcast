# Treadmill core

This ports the UREVO frame reference and history semantics from the owner's treadmill repository.
Only an unavailable transport ships. The recording fake exists in the harnesses, and no code scans,
connects to or writes to hardware. Commands are synchronous functions on `TreadmillCoordinator`;
launcher, hotkey and CLI registration remain outside this core-only port.

## Invariants

- The session follows reported counters, including pause, resume and final frames. Sending a command
  never claims the belt started or stopped. A start times out after 15 seconds; wake retries stop at two.
- Notifications can split or concatenate frames. Checksums and lengths are validated before indexing.
- Resume restores the last moving speed. Nudges accumulate from the last requested speed.
- Every dependency is injected. `Model/` uses Foundation and has no environmental reads.
- History and the current walk share one atomic `treadmill.json` snapshot under
  `Application Support/<bundle identifier>/notchcast/treadmill`. Finishing a walk and removing its
  recovery snapshot therefore commit together. File work runs off the main actor, with one writer.
  Live counters checkpoint every 30 seconds and on phase changes; final counters always flush.
- A failed or corrupt archive is reported and never overwritten. Malformed legacy JSONL lines are
  skipped independently; old folders are read only. Import is committed with its completion flag.
  Only the old treadmill folder supplies lubrication marks; another history source cannot reset them.
- Old JSONL records from the treadmill and Orion walk folders are deduplicated by start timestamp.
  Phone totals are deduplicated by their counters, including across time zones. They contribute to
  period totals and the odometer, but never to daily chart buckets or the walk count.
- The goal defaults to 60 minutes, can count steps or kilometers, and can be disabled through the API.
  Goal preferences live in the channel's fork-local defaults suite. Goal completion is persisted once
  per calendar day. Lube becomes due at each 200 km mark after the last recorded lubrication.
- Walk and history switches are independent of the island. Turning history off gates its commands
  and goal events; the walk still records recovery and finished sessions to avoid losing progress.
- Turning Walk off sends Stop only with a connection, known walk or pending start, then disconnects.
- Stop connects even without a known walk. Toggle queries unknown status and starts only on an idle reply.

## Integration still pending

PR #63's `NotchcastExtrasSection` was not on main at implementation time. The feature enum provides
the two switch rows through the current automatic list; the Extras section can list the same cases.
No permission or entitlement changes are needed for the unavailable transport.

Left for the look: live walk activity, controls, history/chart, goal and lubrication notices, and goal
configuration. `stats()`, `history.archive`, `engine.walk`, `onGoalReached` and `lubeDueMark` expose data
without owning presentation. Hardware behaviour requires separate validation with the owner.
