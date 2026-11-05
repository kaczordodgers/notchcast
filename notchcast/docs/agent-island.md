# Agent Island

## Invariants

- Off by default, visible beside Agent Threads in the Agents settings group.
- Each disabled source is absent from both its presentation and the combined counts.
- Starting observes snapshots only; it never starts source polling or performs I/O.
- No view, island registration or activity is included; visible design awaits approval.

## Model

`AgentIslandEngine` produces equality-stable T3 and OpenBot modes. Priority is approval,
question, failed, working, finished, idle. T3 approval counts use at least one per waiting
thread; questions count threads. Working names are sorted by item ID and capped at three,
with the full count retained. Completed threads show for 5.2 seconds from their source
timestamp using the injected clock. Evaluation after that window expires returns idle.
Failures persist while the source item is unchanged; dismissal records the entire item,
so a changed failure reappears. The summary counts all waiting and working items,
including those hidden by a higher-priority mode.

OpenBot approvals and browser takeovers count as approval attention, prompts as questions;
otherwise its mode is idle. This uses only the landed public data model. No PolyForm
implementation, wording or constants are copied.

## Service

`AgentIslandModule` observes both source snapshots and switch reads while running. Stop
invalidates pending observation callbacks and cancels the owned refresh task. There are no
timers or independent I/O. A later view must call `update()` as its clock advances to expire
finished presentations, and `setVisible(_:)` to forward source polling activity.

The refresh action temporarily pauses polling, refreshes enabled sources and awaits their
existing completion APIs before reporting. Visibility is restored afterward. Opening a T3
item exposes its verified URL to the caller; OpenBot has no open action yet. Failed-item
dismissal is engine-only.

## Commands

Show Agent Status requires only Agent Island. It refreshes enabled sources and reports a
localized waiting/working summary, or “No agents active.” No source is implicitly enabled.

## Cut scope

Answering, approving, stopping and messaging have no verified API and are omitted. The T3
CLI cannot answer. Takeover presentation is folded into approval attention. There is no
dependency on Waiting Alerts, no new UI and no island wiring.

## Verification

`Tests/nc-AgentIsland-engine-test.swift` compiles shipped source models and services with
synthetic inputs and hook-shaped MainActor closures under Swift 6 strict concurrency.
