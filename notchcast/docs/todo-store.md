# Task store

Tasks are local and disabled by default. Our features live in a Notchcast category in the Settings sidebar, one tab per module. Every switch has a working function, and its commands sit under it. Turning a switch off removes its commands. Enabling it starts `TodoModule` through `NotchcastModuleController.Entry(requires: [.tasks], module: tasks)`; disabling it cancels loading, closes the log and releases the store. It has no island dependency or permission grants.

`TodoStore` owns the state under the channel's Application Support directory, in `Todo/commands.jsonl`. Settings shows that directory and, while loaded, the total task count including completed tasks. No workflow sections are created automatically.

## Values and commands

The Foundation-only, `Codable`, `Equatable`, `Sendable` values are `TodoTask` (including `TodoTask.Due`), `TodoProject`, `TodoSection`, `TodoLabel`, `TodoSavedFilter` and `TodoComment`. Each entity has an immutable UUID string `id`; callers supply IDs and dates. `externalRef` preserves a task's imported identifier independently of its local ID. Task descriptions hold Markdown as text.

Priority 1 is least urgent; priority 4 is most urgent and should display as P1. Due dates hold an injected `Date`, optional `DateComponents` time, `isAllDay`, optional `recurrenceRule` and `normalized` text. All-day dates have no time; timed dates require one. This pack does not parse dates or recurrence rules.

`TodoState` exposes read-only dictionaries `tasks`, `projects`, `sections`, `labels` and `filters`. `mutating func apply(_ command: TodoCommand) throws -> TodoCommand` applies atomically and returns an inverse. A rejected command leaves the entire state unchanged; errors are `TodoCommandError` cases.

`TodoCommand` supports task add/update/move/complete/uncomplete/delete; project, section, label and filter add/rename/delete; filter query updates; comments; ordering; and atomic batches. `reorder(kind:orders:)` assigns explicit integer orders by ID for any entity kind. `removeRecord(kind:id:)` lets inverse commands remove exact records without cascading twice; normal callers use the semantic delete commands.

A task's section must belong to its project, and a child must share its parent's project and section. Parent cycles, unknown references, duplicate IDs, duplicate labels and priorities outside 1...4 are rejected. Batches validate their final state, allowing restoration of related values together.

Deleting a task deletes its descendants. Moving it moves its descendants to the destination project and section. Deleting a project deletes its sections and tasks. Deleting a section keeps its tasks in the project with no section. Deleting a label removes it from tasks. All these changes are reversible. Completion affects the selected task only; recurrence is stored without scheduling another task.

## Store API

`@MainActor @Observable final class TodoStore` exposes:

- `static func open(directory: URL) async throws -> TodoStore`
- `func perform(_ command: TodoCommand) throws -> TodoCommand`
- `func undo() throws`
- `func close() throws`
- Read-only `state`, `directory`, `loadWarnings`, computed `canUndo`, and `static let schemaVersion`.

Opening replays the log off the main actor and follows caller cancellation. Short writes remain synchronous to preserve command ordering. Each local record contains `schemaVersion`, `command`, `isUndo` and an `envelope`; undo records replay the inverse and consume one history entry, so undo remains available after reload. A receive record holds one atomic `received` envelope batch. An append is synchronized before observable state changes. If writing fails, rollback truncates only the failed append; rollback failure blocks subsequent writes.

An unterminated last record is reported through `LoadWarning.tornLastLine(line:)` and removed before further appends. Newline marks a committed record. A malformed committed record, an invalid replay command or an unsupported schema fails loading without changing the file. The module reports load failures and recovered tails through the app's HUD. There are no snapshots or schema migrations yet.

The application owns one active store for this directory. `close()` disables further writes even if another caller retains the store. Modules expose `init(directory:showFailure:)`, `start()`, `stop()`, `store` and `directory`; callers should use the services-owned module rather than open a competing writer.

## Replication

The optional Mac Link exchange is described in [todo-sync.md](todo-sync.md).

`TodoReplication(replicaID:)` is the pure replication state. `perform(_:)` validates the command and
returns its inverse, while recording a `TodoEnvelope` containing the replica ID, per-replica sequence,
Lamport timestamp, command and before/after changes for affected records. No wall clock is used.
The store persists its generated UUID replica identity in `replica-id` beside the log. This directory
is one replica's data; copying a live directory to another writer also copies its identity and is not
a way to initialize a second replica. Initialize another store and exchange envelopes instead.

`TodoReplication.merge(local:remote:now:) throws -> TodoReplication` unions envelope identities and
replays their changes in ascending `(timestamp, replicaID, sequence)` order. Re-delivery is idempotent;
different payloads for one identity fail with `TodoReplicationError.conflictingEnvelope`. A new local
command advances beyond the greatest observed Lamport timestamp. Old records without envelopes are
assigned the local replica ID, sequence and Lamport time in log order. Their bytes remain untouched.

The injected wall clock bounds incoming logical ticks to the Unix-millisecond value one day ahead.
An envelope beyond that ceiling is kept in `deferredEnvelopes`, excluded from the applied vector
clock, and reported through typed `clockErrors` (`timestampAhead`, including its ID and retry date).
It cannot advance the local clock. A later merge, including one with an empty remote batch, retries
deferred envelopes against the supplied clock. The store persists these envelopes before returning
the typed errors from `receive(_:now:)`; reopening with `open(directory:now:)` retries them too.

Last write wins applies independently to task title, description, due (the entire `Due` value),
priority, labels (the entire list), location (project/section/parent together), and completed status
(`completedAt`). Order, external reference and claim marker are additional independent fields.
Only changed fields participate: a stale full-task update does not overwrite unrelated newer fields.
Comments merge by immutable comment ID, retaining concurrent additions; conflicting changes to one
comment use the same envelope ordering. Project, section, label and filter properties also merge
independently. Batches and cascades record their complete resulting changes under one timestamp.

A delete removes its record even after earlier edits; a later edit to an absent record is ignored.
An add restoring a deleted ID records the specific deletion it reverses in `restoredFrom`. Undo of
a project deletion therefore cannot restore a subtask independently deleted on another replica;
other outstanding deletions still win in either envelope order. Tasks concurrently added under a
deleted project or missing parent are re-homed to Inbox with their parent cleared. The typed
`orphansRecovered: [TodoOrphanRecovery]` snapshot preserves their IDs and former project/parent IDs
for a later UI report. A deleted section clears a task's section, and deleted labels are removed
from its labels. Concurrent parent cycles detach the repeated node's parent edge during a sorted-ID traversal;
children inherit their surviving root's project and section. These rules repair relationships after
merging so command validation remains true. All envelopes remain available for a later missing
dependency to arrive; an incomplete exchange never destroys its pending edits.

`vectorClock` exposes the greatest contiguous received sequence for each replica, rather than the
greatest observed sequence. `envelopes(after:)` returns everything beyond those prefixes, including
already-received envelopes beyond a gap. A later exchange fills the gap without skipping edits.
`TodoStore.receive(_:)` durably appends a validated batch before publishing its merged state. A receive
containing new envelopes clears local undo history, since inverses could overwrite remote work;
duplicate-only delivery leaves history unchanged. `replication` is a read-only store snapshot.
Envelope IDs are typed `(replicaID, sequence)` values and receive filtering uses a Set. Opening
collects received batches and the enveloped commands between them, merges once after the last receive,
then replays the local tail to reconstruct undo. Ordered new batches extend the cached projection;
out-of-order batches rebuild it deterministically. Projection materialization validates dictionaries
directly rather than synthesizing thousands of add commands and unused inverses.

Callers exchange vector clocks separately and send `replication.envelopes(after: peerClock)`.

## Todoist export import

`TodoistImportMapper.map(_:into:includeCompleted:now:calendar:timeZone:makeID:)` decodes a
fixture-shaped API v1 export into an `ImportReport` with `commands` and
`unparsedRecurrences` (task external references). Apply the commands as one `.batch`.
The mapper validates the complete batch before returning it. IDs, clock and calendar are injected.
Tasks and projects keep `todoist:<id>` in `externalRef`; repeat imports skip existing records.
Sections match by project and name, labels by name. Completed tasks are excluded by default;
when included, their completion date uses the supplied import time.

Exported dates remain authoritative. Recurrence strings pass through `TodoDateParser`; unsupported
rules retain the original due string and date and appear in the report. Comments and notes become
task comments. Attachments and activity history are excluded.

`TodoistExportSource.export() async throws -> Data` is the transport boundary;
`FixtureExportSource(url:)` reads a fixture off-main through
`TodoistImportClient.export(from:)`. No network client or token storage is wired; the Settings import button reads a JSON export.
`Tests/nc-Todo-import-test.swift` uses only the hand-written fake export in `Tests/Fixtures/`.

## Store harness

`Tests/nc-Todo-store-test.swift` exercises all command variants and their inverses, a persisted undo chain, atomic rejection, schema rejection, torn-tail recovery followed by append/reload, module switch lifecycle independent of the island, and a 1,000-command reload below one second. Harness files stay in a UUID directory and never touch a production store.

`Tests/nc-Todo-sync-test.swift` covers convergence in both orders, each task field's independent merge
and conflicting last write, equal-clock ties, deletes versus edits, explicit restoration, relationship
repair, idempotent delivery, vector gaps, old logs, durable received batches, typed failures and JSON
round-trips. It uses UUID temporary directories.
The sync harness compiles with optimization and reports timings for a 10,000-envelope open across
500 receive records and receipt of 100 new envelopes onto 10,000. Timing is diagnostic because CPU
contention changes wall-clock duration; state, persistence and undo remain assertions. It also
guards independent deletion during project undo, Inbox orphan recovery and future-clock quarantine/retry.
