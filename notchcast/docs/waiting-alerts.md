# Waiting-for-you alerts

## Invariants

- Off by default, visible under Agents; requires only Waiting-for-you alerts.
- Engine only: uses the existing neutral message HUD, without a view or island activity.
- The first successful read counts existing waits silently. Each later entry into waiting posts once.
- A change between approval and question while still waiting does not begin a new wait.
- Waiting count only changes when its value changes, ready for a later closed-island mark.

## Model

`WaitingAlertsEngine` compares waiting identifiers, titles and approval/question kinds.
Comparing waiting identifiers suppresses repeats until a thread leaves and re-enters waiting.
New waits coalesce into one notice with the total waiting count; a single new wait names the thread and reason.

## Service

`WaitingAlertsReader` opens `~/.t3/userdata/statev2.sqlite` with `SQLITE_OPEN_READONLY` and a
500 ms busy timeout, off the main actor. Each read executes one grouped query joining runtime
requests to threads, excluding resolved requests and archived or deleted threads. `user_input`
means question; every other kind means approval. Approval wins when both occur on a thread.
The connection closes after each read. No CLI process or Agent Threads dependency is involved.

T3's internal schema is not a public contract. If an update changes it, a missing table or SQL error
sets the failure state and the command reports “T3 data is unavailable.” Nothing crashes.
Missing database files fail without creating a file.

Upstream's `FileSystemWatcher` observes the local userdata directory (one-second latency, no timer
or throttle). Only changes to files directly in it count, where T3 keeps its state database; writes in
subfolders such as logs and attachments are ignored. Missing directories create no stream; enabling again retries watcher creation.
Changes during a read coalesce into exactly one trailing read; reads never overlap.
Stop closes the stream, cancels its owned task and invalidates late callbacks and results.
Failed reads preserve the previous successful snapshot; explicit commands report failure.

## Commands

Show Waiting Agents reads immediately and reports zero, the localized waiting count, or failure.
If a read is in flight, the command queues a read immediately after it. Only the Waiting-for-you
alerts switch gates the command. Module start/stop refresh command availability.

## Cuts

Private agent status reports are out of scope.
Remote Mac coverage belongs to fleet-panel. Click-to-open also waits for fleet-panel; the existing
Open Waiting Agent Thread command already handles opening. Mark rendering waits for a design decision.

## Verification

`./Scripts/run-tests.sh nc-WaitingAlerts-engine-test` uses synthetic snapshots, watcher events,
suspended reads and SQLite databases in the system temp folder, including a schema-missing database.
It compiles the production module with the exact hook closure and Swift 6 complete strict concurrency.
It never watches the real userdata directory or opens the real database.
