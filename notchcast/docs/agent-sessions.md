# Agent session metadata

## Invariants

- The feature defaults off. Enabling it performs no filesystem scan until a consumer requests a refresh.
- Only metadata and usage aggregates survive parsing. Prompts, replies, tool arguments and credentials are never retained, persisted or sent over the network.
- Every path is checked before filesystem access. A path with a component starting with a prefix from the private `NOTCHCAST_AGENT_SESSIONS_EXCLUDE` key (see `notchcast/README.md`) is rejected, including an injected scan root. Symlinks are skipped, including in root ancestors and SQLite sidecars.
- JSONL reads are bounded to 64 KiB and individual lines to 256 KiB. Incomplete lines wait for a newline; malformed or oversized lines do not prevent later records from being indexed.
- The index and its snapshots are `Sendable` values. The module owns cancellation and rejects results from an earlier operation after stopping or refreshing.

## Locations and formats

`AgentSessionIndex.Root.defaults(home:)` builds paths without accessing them: `.claude/projects`, `.config/claude/projects`, `.codex/sessions`, `.codex/archived_sessions`, `.copilot/session-state`, and `.local/share/opencode/opencode.db`. Callers can inject additional explicit roots for another configuration directory. Discovery does not enumerate the home directory.

Claude metadata comes from user and assistant JSONL records; assistant usage carries input, output and cache counts. Codex reads session metadata, turn context, explicit usage records and cumulative token-count events. Copilot reads context and model events plus cumulative per-model shutdown metrics. Missing timestamps and models remain unknown; usage without a timestamp is not assigned to an invented day.

OpenCode uses a read-only SQLite connection with `query_only` and a read transaction. Both `session`/`message` and `session_v2`/`session_message` schemas are supported. SQL selects only metadata fields from message JSON. Unsupported schemas and inaccessible files appear in `Snapshot.issues`; a missing root is an empty source.

## Consumer API

`NotchcastCore.agentSessions` exposes the module and its observable `pricingReport`. The gated Refresh Agent Session Logs command calls `refresh()`, which runs one scan; nothing polls. `stop()` cancels work and releases the index, snapshot and priced totals. No island page or FSEvents watcher is installed.

`AgentSessionIndex.refresh(roots:)` is the synchronous service boundary for callers already off the main actor. It returns sessions, source issues and read statistics. JSONL checkpoints use inode, size, modification time and byte offset; replacement or truncation resets a file. Database checkpoints use session creation/update times, message update times and row counts; changed sessions are rebuilt so in-place updates replace prior totals. Deleted sources and sessions are evicted.

`AgentSession` contains a provider-qualified `id`, provider, project directory, first and last activity, latest explicit completion, current model and `usage`. `isWorking(at:)` considers explicit completion and ten minutes of silence. Completion describes the latest observed turn; it does not claim that a process exited. Process liveness is not probed.

Pricing consumes `AgentSession.usage`, grouped by model and day in the index's injected calendar, captured at index creation. Each `Usage` carries an optional model, `day`, `tokens` and optional OpenCode `reportedCost` in USD. `Tokens.input` excludes cache reads/writes; `output` includes reasoning and `reasoning` is an informational subset. OpenCode's separate output and reasoning counts are normalized into that same shape. Unknown usage is an empty array rather than a fabricated estimate.

Files sharing a native session ID contribute usage to one session. Metadata comes from the latest activity; usage is summed by model and day. Unchanged sessions and issues do not republish the module snapshot, whose read statistics describe its last publication. Pricing observes only its preference and recalculates on a session change or when enabled. The bundled pricing engine is decoded once; dated model IDs fall back to the undated price.

Streamed response deduplication retains the latest 256 response IDs per file. Codex running totals and Copilot per-model totals are reduced to deltas. A historical replay beyond that response window can count again. Checkpoints are memory-only and rebuild lazily after relaunch. Same-inode rewrites that grow a file are treated as appends; producers are expected to replace or truncate logs when rewriting history.

## Verification

`./Scripts/run-tests.sh notchcast-ai-agent-session-logs-test` compiles the shipped model, services, module and switch with strict concurrency and warnings as errors. It uses only generated temporary fixtures and covers all four formats, both database schemas, malformed lines, a 24 MiB oversized line, partial appends, replacement, truncation, deletion, model changes, cumulative counters, demand and cancellation. An access observer fails before any filesystem operation on an excluded component; the excluded fixture is an empty directory removed with `rmdir`, without opening it.

Format references are the catalogue's documented reader source paths. Vendor format context: [Codex protocol](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs) and [OpenCode source](https://github.com/anomalyco/opencode). No local agent logs were inspected during implementation. A full app build and live checks belong to landing verification.
