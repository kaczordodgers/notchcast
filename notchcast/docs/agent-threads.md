# Agent Threads

## Invariants

- Disabled by default; disabling removes both launcher commands and cancels work.
- Reads only the T3 CLI; never opens its database or calls its server directly.
- Waiting threads precede active threads and threads finished within the last 30 minutes.
- No island page or new view is included.

## Model

`AgentThreadParser` decodes list arrays or a threads envelope, plus show envelopes. Unknown statuses become stale. Invalid JSON fails the refresh. The clock is injected into selection. Pending counts come from show for non-settled threads; a positive count indicates approval waiting unless the status explicitly indicates input waiting.

## Service

`AgentThreadsState` refreshes on start and command invocation. `setActive` enables 15-second polling for a future page; inactive has no timer. Stop cancels work and invalidates its operation identity. The injected runner permits synthetic harnesses. Production resolves executable absolute paths and enforces a ten-second timeout.

## Commands

Refresh Agent Threads updates the snapshot. Open Waiting Agent Thread opens the first waiting link or reports a neutral message. Both commands require the Agent Threads switch in Activities.

## Verification

`./Scripts/run-tests.sh nc-AgentThreads-engine-test` compiles the shipped model and service with fake CLI responses. Live server access and visual presentation are outside this engine change.
