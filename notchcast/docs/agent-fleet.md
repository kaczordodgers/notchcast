# Agent fleet wiring

T3 Threads, Waiting Alerts, Fleet panel, Agent Island and Bot Host have independent,
default-off switches in Notchcast Settings. No new island surface is installed.
T3 polling runs only while T3 Threads is enabled and a consumer requests snapshots.
`T3Threads` projects that shared snapshot into alerts, local fleet rows and island state.
Waiting Alerts uses snapshot changes rather than a second filesystem reader and posts
through `IslandActivityCenter`'s existing status-message seam.

The fleet's remote source remains unconfigured and reports the existing expired-link
state. Bot Host requires an injected client; read commands report its absence plainly.
List Bots, Bot Status and Bot Pending use the command catalog and follow Bot Host's
switch. Status and pending read every listed bot; they do not select or act for the user.
Command deep links retain the shared consent policy.

Message, answer and approve commands remain deferred until a user interface exists.
Remote fleet transport and live checks remain deferred. OpenBot's `/api/list`,
`/api/status`, `/api/pending`, `/api/message`, `/api/answer` and `/api/approve`
contracts are assumptions requiring verification against the host implementation.

`notchcast-agent-fleet-wiring-test` injects a synthetic T3 transport and proves fanout
and independent switch teardown without reading local agent data.
