# Task sync over Mac Link

The default-off **Sync tasks between Macs** preference requires both Tasks and Mac Link.
Both Macs must opt in and already be paired.
The preference is excluded from settings
backups because importing settings must not grant access to task replication.

## Protocol

`todo-sync` uses the existing authenticated Mac Link request channel. The reply preserves the
request's method and correlation ID. `TodoLinkCoordinator.live` registers the route, which refuses
unless the coordinator can sync.

Both directions carry `TodoLinkPacket`: `clock` is the sender's applied, contiguous per-replica
`TodoVectorClock`; `envelopes` is an ordered batch the recipient lacks; `hasMore` says the batch
was limited by size. Store attachment and switch activation start with no assumed peer clock, so
they may retransmit acknowledged records; later exchanges reuse the last reply clock in memory.
The responder applies and synchronizes the batch
through `TodoStore.receive` before reporting its clock, then returns envelopes after the request's
clock. The requester persists that response through the same store API and continues until neither
side has missing envelopes. Each packet's JSON stays below 40,000 bytes to leave room for Mac Link's
base64 payload and framing within its 65,536-byte limit. Larger envelopes use 20 KB byte chunks of
sorted-key JSON with envelope identity, total length, offset and SHA-256 digest. The receiver returns
its contiguous offset in `receipt`; retries resend unacknowledged bytes idempotently. Only a complete,
verified envelope enters the strict store merge. One pending envelope is retained per coordinator,
bounded to 8 MB; teardown drops partial bytes. A merge that cannot advance either applied clock stops the exchange
instead of spinning on quarantined envelopes.

The existing per-field last-write-wins order `(timestamp, replicaID, sequence)` and comment-ID merge
remain authoritative. No separate sync database, acknowledgement file or mutable outbox is needed:
all envelopes and replica IDs remain in the durable store. A failed request or dropped response
therefore loses nothing, retries are idempotent, and reopening reconstructs the receipt clock.

## Ownership and triggers

`TodoModule` reports store open/close through two callbacks. The Todo-owned `TodoLinkCoordinator`
attaches to the active store and starts an exchange when enabled and when the store opens. Successful
local commits, including undo and agent writes, debounce another exchange by two seconds. Receives
do not trigger exchanges, preventing reciprocal request storms. There is no polling or automatic
failure retry: the next local commit, store open or switch activation retries retained envelopes.
An enabled peer can also initiate an exchange and retrieve this Mac's pending changes.

Only one outgoing exchange runs at a time, even while cancelling and immediately restarting.
Stopping either dependency or closing the store cancels debounce and request work. Cancellation,
the current store generation, feature eligibility and pairing identity are validated before applying
a reply. Peer responses refuse while disabled or while the store is unavailable. Request failures
are logged through `TodoSync` and shown through the module's existing failure message path, once per
failure kind until a successful exchange. Conflicting envelopes report a possible shared replica ID;
oversized transfers report the 8 MB limit. Local task editing remains available.

`Tests/nc-Todo-link-test.swift` uses an asynchronous fake request channel and temporary stores;
it never connects to a real peer. It covers convergence, field conflicts, retransmission, paging,
switch gates, durable reload and teardown.
