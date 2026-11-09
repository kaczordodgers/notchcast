# Task list queries

The engine owns no UI, preferences or clock. Construct `TodoViews(state:now:calendar:)` from a store
snapshot and the caller's clock and calendar, including its time zone. Rebuild the value when any of
those inputs changes. Queries never mutate the snapshot.

## API

- `inbox(options:) -> [TodoTaskGroup]`: tasks without a project.
- `today(options:) -> [TodoTaskGroup]`: overdue tasks and tasks due on the supplied calendar day.
- `upcoming(days:options:) -> [TodoDayBucket]`: overdue first, then exactly `days` calendar days,
  starting today. Empty buckets remain present, including overdue; nonpositive days returns no buckets.
- `project(id:options:) -> [TodoTaskGroup]`: defaults to section grouping, with the unsectioned group
  first and every section in manual order, including empty sections. Subtasks nest under their parents.
- `label(name:options:) -> [TodoTaskGroup]`: case-insensitive label-name lookup, matching label IDs on
  tasks. Missing labels return an empty group; missing projects return no groups.

`TodoTaskNode` contains `task` and recursive `subtasks`. `TodoTaskGroup` contains a typed `id` and
`tasks`. `TodoDayBucket` contains an overdue/day `id` and `groups`, so grouping also works within each
Upcoming day. Flat lists include matching subtasks independently; project lists nest matching tasks
within each group. If a parent is hidden or belongs to another group, its visible child becomes a root
there.

## Ordering and options

Completed tasks are excluded by default. `TodoViewOptions` is a plain `Codable`, `Equatable`, `Sendable`
value with `grouping`, `sorting` and `includeCompleted`. The later settings layer saves a
`[String: TodoViewOptions]` keyed by its view IDs; there is no new command or persisted store schema.
Presentation preferences do not belong in the task undo log.

Grouping supports none, project, section, priority, due date and label. Project, section and label
groups follow entity order with UUID ties; absent project/section/label comes first. Sections across
projects follow project order first. Priority groups run 4 through 1. Due groups run earliest day first
and undated last. Multi-label tasks appear in each matching label group.

Sorting supports manual order, due ascending, priority descending, name ascending and added ascending.
Name ordering compares lowercased Unicode strings without ambient locale rules. Missing due dates
and added dates sort last. Every sort falls back to manual order, then UUID, so dictionary iteration
cannot change results. `TodoTask.addedAt` is optional and caller-supplied: old records decode without
it and use manual order among undated additions. Task creation callers must supply it for new tasks.

With default sorting, Today and each Upcoming bucket order by due instant, priority 4 through 1,
manual order, then UUID. Overdue means before today's calendar boundary and stays ahead of today within
each group for every Today sort. A timed task earlier today remains in today's Upcoming bucket. All-day due dates
sort at local midnight; timed `due.date` values are fixed instants and `due.time` is display metadata.
Calendar addition defines day boundaries, preserving short, long and repeated-hour DST days.

## Proof

`nc-Todo-views-test` compiles only shipped model files. It covers every query, grouping and sorting
choice, Codable options and older task records, midnight rollover, both DST transitions and repeated
hours, empty Upcoming days and project nesting. There are no views, window, island page or additional feature switch.
