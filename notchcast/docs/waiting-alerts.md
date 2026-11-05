# Waiting-for-you alerts

## Invariants

- Off by default, visible under Agents; requires Agent Threads and Waiting-for-you alerts.
- Engine only: uses the existing neutral message HUD, without a view or island activity.
- The first successful read counts existing waits silently. Each later entry into waiting posts once.
- A change between approval and question while still waiting does not begin a new wait.
- Waiting count only changes when its value changes, ready for a later closed-island mark.

## Model

`WaitingAlertsEngine` projects Agent Threads snapshots into identifiers, titles and approval/question
kinds. Comparing waiting identifiers suppresses repeats until a thread leaves and re-enters waiting.
New waits coalesce into one count notice; a single wait names the thread and reason.

## Service

`WaitingAlertsModule` reads `NotchcastCore.agentThreads.state` through its existing public API.
No Agent Threads behavior or access level changes. FSEvents observes the local userdata directory
with 2.5-second latency. It never writes there. Missing directories create no stream and the command
reports unavailability. Enabling again retries watcher creation.

An injected monotonic clock and cancellable one-shot sleep enforce ten seconds between refresh
starts. Changes during work or the gap coalesce into one trailing refresh; work never overlaps.
Stop closes the stream, cancels its owned task and invalidates late callbacks and results.
Failed reads preserve the previous successful snapshot; explicit commands report failure.

## Commands

Show Waiting Agents requests a refresh through the same throttle and reports zero, the localized
waiting count, or failure. Both switches gate the command. Module start/stop refresh command availability.

## Cuts

Chad lead QUESTION:/BLOCKED: reports use a private event router, outside the T3 contract.
Remote Mac coverage belongs to fleet-panel. Click-to-open also waits for fleet-panel; the existing
Open Waiting Agent Thread command already handles opening. Mark rendering and all new visible design
wait for Damian.

## Verification

`./Scripts/run-tests.sh nc-WaitingAlerts-engine-test` uses synthetic snapshots, watcher events,
clock and suspended reads. It compiles the production module with the exact hook closure and
Swift 6 complete strict concurrency. It never watches the real userdata directory.
