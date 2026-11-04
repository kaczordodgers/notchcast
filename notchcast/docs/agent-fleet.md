# Agent fleet wiring

T3 Threads, Waiting Alerts, Fleet Panel, Agent Island and Bot Host have independent,
default-off switches in Notchcast Settings. No new island surface is installed.
T3 polling runs only while T3 Threads is enabled and a consumer requests snapshots.
`T3Threads` projects that shared snapshot into alerts, local fleet rows and island state.
Waiting Alerts uses snapshot changes rather than a second filesystem reader and posts
through `IslandActivityCenter`'s existing status-message seam.

The remote environment ID defaults to empty, yielding local-only data. A configured
remote destination reports the expired-link state until a remote source is supplied.
Bot Host reads its loopback URL from feature settings and its token from Keychain
at request time; settings can save the token without displaying an existing secret.
List Bots, Bot Status and Bot Pending use the command catalog and follow Bot Host's
switch. Status and pending read every listed bot; they do not select or act for the user.
Command deep links retain the shared consent policy.

Message, answer and approve commands remain deferred until a user interface exists.
Remote fleet transport and live checks remain deferred. OpenBot's `/api/list`,
`/api/status`, `/api/pending`, `/api/message`, `/api/answer` and `/api/approve`
contracts are assumptions requiring verification against the host implementation.

`notchcast-agent-fleet-wiring-test` injects a synthetic T3 transport and proves fanout
and independent switch teardown without reading local agent data.

Host protocol attribution and license: [notice](bot-host-notice.md), [license](bot-host-license.txt).
