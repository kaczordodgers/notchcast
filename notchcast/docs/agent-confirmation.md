# Agent confirmation

The confirmation engine queues one request at a time. Its default outcome is denial (exit code 5).
Only the local coordinator choice API can approve; inbound parameters never carry authority.
Deadlines expire queued as well as visible requests. Duplicate IDs invalidate a pending request and
cannot be replayed during the coordinator lifetime. Always allow delegates to AgentGrantStore and
is restricted to parameterless consent-class actions; parameterized actions ignore stored grants and offer only Allow once and Deny. Dangerous actions need an explicit choice every time.

A dialog closes when its request times out, is cancelled or the bridge stops; requests queued behind it time out as Deny (exit 5).
An approved action retains the prompt queue until its run returns, including any upstream confirmation; while an unrelated dialog is open, an agent request is denied immediately (exit 5).

## Integration boundary

AgentConfirmationActions supplies trusted action classifications, independently of request payloads.
PR #82's action layer must adopt it; no action registry or audit engine is duplicated here.
The future AppCore-owned adapter must construct the coordinator with the fork preferences switch,
feed authenticated transport requests, call tick with the clock while running and stop on teardown,
and render engine.current. It must keep upstream-confirming actions on their existing dialog path.
AgentConfirmationTransport only sends replies; its fake in the harness drives incoming requests.
Production transport, island card and audit dispatch remain with the action integration.
No service is started by this engine-only change.

## Verification

Run `./Scripts/run-tests.sh nc-AgentConfirm-engine-test` for FIFO, local approval and denial,
grant persistence, dangerous always-allow rejection, timeout, duplicate, malformed, disable and stop.
