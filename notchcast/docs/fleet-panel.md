# Fleet Panel

## Invariants

- Off by default, visible in Agents; switching off removes Show Fleet and cancels owned work.
- Engine only: no page, view, or island activity. Visible design waits for an approved mockup.
- Reads on start and explicit refresh only. No periodic reads or activation of Agent Threads polling.
- Local and remote reads begin in parallel; stopped and superseded operations cannot publish.
- Failures are column states, never successful empty lists.

## Model

Each Mac has rows, sourceOff, linkDown, remoteOff, or failed state. Waiting rows precede working
rows, followed by finished rows updated in the last 30 minutes (inclusive). Ties use update time
then ID. Rows carry only ID, title, project, model, phase, pending count, link and update time.
`updatedAgo(now:)` is time since the last update, clamped at zero. It is not run length: the public
source has no run-start timestamp. The clock is injected. Idle and unknown (`stale`) rows are excluded.
Waiting and working totals are computed independently for each column. Equality is value based.

## Service

FleetLocalSource joins a loading Agent Threads state, or starts one refresh without a callback and
waits until idle. If a user refresh supersedes that work, Fleet joins the replacement. Concurrent Fleet
reads never cancel each other or a user's completion callback. Agent Threads itself is unchanged.
The responder bounds its read to 20 seconds, below Mac Link's 26-second responder budget, returning
failed on timeout without cancelling shared Agent Threads work. Agent Threads off produces sourceOff
locally and remoteOff remotely.
FleetMachLinkTransport uses the same configured endpoint / uniquely paired Bonjour peer selection
as remote fans and checks destination identity after suspension. Unpaired, missing and unreachable
peers produce linkDown; other errors produce failed. The route refuses requests when Mac Link is off and returns an
off snapshot when Fleet Panel is off. It sends a small Codable snapshot, never configuration or secrets.

## Commands

Show Fleet refreshes both columns and reports one localized message with each Mac's waiting and
working counts or plain failure state. Each Mac's sentence is a single localized literal with separate
plural substitutions for both counts. The command requires fleetPanel only; Mac Link is optional
so local threads remain useful while the link is down.

## Cuts

Lead/worker structure, venture, weight and cap use are private assistant data without a public
contract. Plans already belongs to AI Usage. T3 linked-environment reads have no CLI option or
server-session engine, so the paired Notchcast supplies the remote snapshot over Mac Link.
Outside Claude or Codex sessions are excluded: only T3 Code threads belong here.

## Verification

Tests/nc-FleetPanel-engine-test.swift uses synthetic rows and injected transports, never live data.
No local Xcode build, pairing, remote-machine access, push, PR or workflow is part of this engine task.
