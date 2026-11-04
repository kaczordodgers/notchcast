# Local host client provenance

CodyncHostClient.swift is a reduced and modified adaptation of CodyncKit's
Client/HostClient.swift, Client/HostTransport.swift and Models/Models.swift at
commit 1055636 of https://github.com/leepokai/Codync, copyright 2026 Po Kai Lee.
That pinned revision is MIT licensed; its licence is reproduced alongside this notice.
The repository's current Apache-2.0 licence does not replace the pinned MIT notice.
Changes include on-demand snapshots, minimal wire projections, injected credentials,
private networking, destination checks and sanitised errors. No branding is used in UI.

OpenBotBridge.swift is independently written from the catalogue's six operations.
Its routes and shapes, contained in that one Swift file, are synthetic assumptions,
not verified application APIs.
No PolyForm source was available or copied.

The connection provider is supplied by the caller, reads credentials at use, and
must obtain secrets from Keychain. There is no filesystem discovery or default URL.
The module starts disabled; enabling it does not make a request. Callers own and
cancel their async operations; stopped or reconfigured modules reject stale results.
The host API is pinned for wire shape only; runtime version compatibility is unverified.
For the host client, message/answer report send acknowledgement, while status reports
the bot's current runtime state. Answer sends ordinary chat text; approve responds
to a pending permission option after checking the entry belongs to the requested bot.
The event projection parses supplied data only and never opens a subscription.
