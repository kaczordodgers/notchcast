# Task store

Tasks are local and disabled by default. Settings > Notchcast has a separate Tasks section. Enabling it starts `TodoModule` through `NotchcastModuleController.Entry(requires: [.tasks], module: tasks)`; disabling it cancels loading, closes the log and releases the store. It has no island dependency or permission grants.

`TodoStore` owns the state under the channel's Application Support directory, in `Todo/commands.jsonl`. Settings shows that directory and, while loaded, the total task count including completed tasks. No workflow sections are created automatically.

## Values and commands

The Foundation-only, `Codable`, `Equatable`, `Sendable` values are `TodoTask` (including `TodoTask.Due`), `TodoProject`, `TodoSection`, `TodoLabel`, `TodoSavedFilter` and `TodoComment`. Each entity has an immutable UUID string `id`; callers supply IDs and dates. `externalRef` preserves a task's imported identifier independently of its local ID. Task descriptions hold Markdown as text.

Priority 1 is least urgent; priority 4 is most urgent and should display as P1. Due dates hold an injected `Date`, optional `DateComponents` time, `isAllDay`, optional `recurrenceRule` and `normalized` text. All-day dates have no time; timed dates require one. This pack does not parse dates or recurrence rules.

`TodoState` exposes read-only dictionaries `tasks`, `projects`, `sections`, `labels` and `filters`, plus `static let workflowSections`. `mutating func apply(_ command: TodoCommand) throws -> TodoCommand` applies atomically and returns an inverse. A rejected command leaves the entire state unchanged; errors are `TodoCommandError` cases.

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

Opening replays the log off the main actor and follows caller cancellation. Short writes remain synchronous to preserve command ordering. Each record contains `schemaVersion`, `command` and `isUndo`; undo records replay the inverse and consume one history entry, so undo remains available after reload. An append is synchronized before observable state changes. If writing fails, rollback truncates only the failed append; rollback failure blocks subsequent writes.

An unterminated last record is reported through `LoadWarning.tornLastLine(line:)` and removed before further appends. Newline marks a committed record. A malformed committed record, an invalid replay command or an unsupported schema fails loading without changing the file. The module reports load failures and recovered tails through the app's HUD. There are no snapshots or schema migrations yet.

The application owns one active store for this directory. `close()` disables further writes even if another caller retains the store. Modules expose `init(directory:showFailure:)`, `start()`, `stop()`, `store` and `directory`; callers should use the services-owned module rather than open a competing writer.

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
`TodoistImportClient.export(from:)`. No network client, token storage or settings button is wired.
`Tests/nc-Todo-import-test.swift` uses only the hand-written fake export in `Tests/Fixtures/`.

## Store harness

`Tests/nc-Todo-store-test.swift` exercises all command variants and their inverses, a persisted undo chain, atomic rejection, schema rejection, torn-tail recovery followed by append/reload, module switch lifecycle independent of the island, and a 1,000-command reload below one second. Harness files stay in a UUID directory and never touch a production store.
