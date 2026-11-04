# Agent Threads

## Invariants

- Disabled by default; disabling removes both launcher commands and cancels work.
- Reads only active project IDs and titles from `projection_projects` in the local state database; thread data comes from the CLI, with no direct server calls.
- Waiting threads precede active threads and threads finished within the last 30 minutes.
- No island page or new view is included.

## Model

`AgentThreadParser` decodes list arrays or a threads envelope, plus show envelopes. Preparing, queued and starting map to starting; running stays running; waiting maps to approval waiting when its pending count is positive, otherwise input waiting. Completed stays completed; failed, interrupted, cancelled and rolled_back map to failed. Missing or null status means idle; idle and unknown statuses become stale. Invalid JSON or an unsupported top-level shape fails the refresh; unusable rows are dropped individually. Links accept HTTPS, t3-thread, and HTTP only on localhost or 127.0.0.1. The clock is injected into selection. Only starting, running and waiting list rows fetch show details, one process each; idle and finished rows require no show calls.

## Service

`AgentThreadProjects` opens `~/.t3/userdata/statev2.sqlite` read-only with a 500 ms busy timeout, selects only non-deleted, non-archived projects, and closes immediately. Missing files or tables report unavailable or failed. The project reader and CLI runner are injected for synthetic harnesses. Each project gets `thread list --project <project_id> --json`; its database title supplies the project name, while list rows decode `projectId`. Failed project lists are skipped; all failed lists fail the refresh. Failed show calls preserve the list phase. An empty project list is ready with no threads.

`AgentThreadsState` refreshes on start and command invocation. `setActive` enables 15-second polling for a future page; inactive has no timer. Cancelling a refresh restores ready when a snapshot exists, otherwise idle. Stop cancels work and invalidates its operation identity. Production resolves executable absolute paths and enforces a ten-second timeout. Module start and stop notify launcher command availability.

## Commands

Refresh Agent Threads updates the snapshot and reports the waiting count or CLI failure. Automatic refreshes stay silent. Open Waiting Agent Thread refreshes before opening the first waiting link, and reports CLI failures separately from an empty waiting list. Both commands require the Agent Threads switch in Activities.

## Verification

`./Scripts/run-tests.sh nc-AgentThreads-engine-test` compiles the shipped model and service with fake CLI responses. Live server access and visual presentation are outside this engine change.
