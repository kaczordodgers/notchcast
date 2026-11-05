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
with the full count retained. Any observed non-completed phase transitioning to completed
starts a 5.2-second window at the injected clock. An initially completed item instead uses
its source timestamp and expires 5.2 seconds after that timestamp.
The newest observed completion wins. Repeated snapshots never restart its window.
Failures persist while the source item is unchanged; dismissal records the entire item,
so a changed failure reappears. A missing or disabled source preserves dismissals until a
different version of that item is observed. The summary counts all waiting and working items,
including those hidden by a higher-priority mode.

OpenBot approvals and browser takeovers count as approval attention, prompts as questions;
otherwise its mode is idle. This uses only the landed public data model. No PolyForm
implementation, wording or constants are copied.

## Service

`AgentIslandModule` observes both source snapshots and switch reads while running. Stop
invalidates pending observation callbacks and cancels the owned refresh task. There are no
timers or independent I/O. A later view must call `update()` as its clock advances to expire
finished presentations, and `setVisible(_:)` to forward source polling activity.

The refresh action keeps T3 polling active and uses its first-pass completion callback.
An already running source refresh is joined rather than cancelled. Only OpenBot polling is
paused. Every command explicitly refreshes enabled OpenBot after its existing work finishes,
including after an external stop/start invalidates the island's remembered polling state.
Resuming OpenBot necessarily triggers one immediate extra pass through its public API;
avoiding that requires a source API change, outside this engine's scope. Activity is forwarded
only when its value changes; an island that was never visible forwards no activity calls.
Opening a T3
item exposes its verified URL to the caller; OpenBot has no open action yet. Failed-item
dismissal is engine-only.

## Commands

Show Agent Status requires only Agent Island. It refreshes enabled sources and reports a
localized waiting/working summary, or “No agents active.” No source is implicitly enabled.
Plural variations follow the interpolated-count rule in `docs/standards.md`, including locales
whose count-neutral wording has identical variants.
Spanish, French, Portuguese and Russian keep inflected words inside each count's plural
variant. English, German, Japanese, Korean and Chinese use count-neutral wording.

## Cut scope

Answering, approving, stopping and messaging have no verified API and are omitted. The T3
CLI cannot answer. Takeover presentation is folded into approval attention. There is no
dependency on Waiting Alerts, no new UI and no island wiring.

## Verification

`Tests/nc-AgentIsland-engine-test.swift` compiles shipped source models and services with
synthetic inputs and hook-shaped MainActor closures under Swift 6 strict concurrency.
