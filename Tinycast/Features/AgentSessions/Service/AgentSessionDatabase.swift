import Foundation
import SQLite3

struct AgentSessionDatabase: Sendable {
    let calendar: Calendar
    private struct Checkpoint: Sendable, Equatable {
        let created: Int64
        let updated: Int64
        let messageUpdated: Int64
        let count: Int64
    }

    private enum Failure: Error { case sqlite(Int32) }
    private var inode: UInt64 = 0
    private var checkpoints: [String: Checkpoint] = [:]
    private var indexed: [String: AgentSession] = [:]
    var sessions: [AgentSession] { Array(indexed.values) }
    private(set) var rowsRead = 0

    mutating func refresh(url: URL, inode: UInt64, onAccess: @Sendable (URL) -> Void) throws {
        onAccess(url)
        var database: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        defer { sqlite3_close(database) }
        guard status == SQLITE_OK else { throw Failure.sqlite(status) }
        sqlite3_busy_timeout(database, 100)
        try execute(database, "PRAGMA query_only = ON")
        try execute(database, "BEGIN")
        defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }
        let tables = try prepare(database, "SELECT name FROM sqlite_master WHERE type = 'table'")
        defer { sqlite3_finalize(tables) }
        var names: Set<String> = []
        try rows(tables) { names.insert(text(tables, 0) ?? "") }
        let sessionTable = names.contains("session_v2") ? "session_v2" : "session"
        let messageTable = names.contains("session_message") ? "session_message" : "message"
        let query = """
            SELECT s.id, s.directory, s.time_created, s.time_updated, max(m.time_updated), count(m.id)
            FROM \(sessionTable) s LEFT JOIN \(messageTable) m ON m.session_id = s.id
            GROUP BY s.id
            """
        let statement = try prepare(database, query)
        defer { sqlite3_finalize(statement) }
        var nextCheckpoints: [String: Checkpoint] = [:]
        var nextIndexed: [String: AgentSession] = [:]
        rowsRead = 0
        try rows(statement) {
            try Task.checkCancellation()
            guard let id = text(statement, 0) else { return }
            let checkpoint = Checkpoint(created: sqlite3_column_int64(statement, 2),
                updated: sqlite3_column_int64(statement, 3), messageUpdated: sqlite3_column_int64(statement, 4),
                count: sqlite3_column_int64(statement, 5))
            nextCheckpoints[id] = checkpoint
            if self.inode == inode, checkpoints[id] == checkpoint, let session = indexed[id] {
                nextIndexed[id] = session
                return
            }
            var accumulator = AgentSessionAccumulator(provider: .opencode, id: "opencode:" + id, calendar: calendar)
            accumulator.context(project: text(statement, 1), model: nil)
            accumulator.activity(at: AgentSessionAccumulator.date(checkpoint.created))
            try readMessages(database, table: messageTable, id: id, accumulator: &accumulator)
            nextIndexed[id] = accumulator.session
        }
        self.inode = inode
        checkpoints = nextCheckpoints
        indexed = nextIndexed
    }

    private mutating func readMessages(_ database: OpaquePointer?, table: String, id: String,
                                       accumulator: inout AgentSessionAccumulator) throws {
        let query = """
            SELECT time_created,
                CASE WHEN json_valid(data) AND length(data) <= 262144 THEN json_extract(data, '$.role') END,
                CASE WHEN json_valid(data) AND length(data) <= 262144
                    THEN coalesce(json_extract(data, '$.modelID'), json_extract(data, '$.model_id'),
                        json_extract(data, '$.model.id')) END,
                CASE WHEN json_valid(data) AND length(data) <= 262144 THEN json_extract(data, '$.tokens') END,
                CASE WHEN json_valid(data) AND length(data) <= 262144 THEN json_extract(data, '$.time.completed') END,
                CASE WHEN json_valid(data) AND length(data) <= 262144 THEN json_extract(data, '$.cost') END,
                CASE WHEN json_valid(data) AND length(data) <= 262144 THEN json_extract(data, '$.finish') END
            FROM \(table) WHERE session_id = ? ORDER BY time_created, id
            """
        let statement = try prepare(database, query)
        defer { sqlite3_finalize(statement) }
        let bound = id.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard bound == SQLITE_OK else { throw Failure.sqlite(bound) }
        try rows(statement) {
            try Task.checkCancellation()
            rowsRead += 1
            let date = AgentSessionAccumulator.date(sqlite3_column_int64(statement, 0))
            let role = text(statement, 1)
            guard ["user", "assistant", "compaction"].contains(role ?? "") else { return }
            let completed = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil : AgentSessionAccumulator.date(sqlite3_column_double(statement, 4))
            let finish = text(statement, 6)
            let ended = role == "assistant" && completed != nil && !["tool-calls", "unknown"].contains(finish ?? "")
            accumulator.activity(at: completed ?? date, ended: ended)
            guard role == "assistant" || role == "compaction" else { return }
            let model = text(statement, 2)
            accumulator.context(project: nil, model: model)
            let cost = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5)
            let raw = text(statement, 3)
            let tokens = raw.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
            guard raw != nil || cost != nil else { return }
            let cache = tokens["cache"] as? [String: Any] ?? [:]
            let reasoning = AgentSessionAccumulator.count(tokens["reasoning"])
            var normalized = AgentSession.Tokens(input: AgentSessionAccumulator.count(tokens["input"]),
                cacheRead: AgentSessionAccumulator.count(cache["read"]),
                cacheWrite: AgentSessionAccumulator.count(cache["write"]),
                output: AgentSessionAccumulator.count(tokens["output"]),
                reasoning: reasoning)
            normalized += .init(output: reasoning)
            accumulator.addUsage(normalized, model: model, at: date,
                cost: cost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
        }
    }

    private func prepare(_ database: OpaquePointer?, _ query: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard status == SQLITE_OK else {
            sqlite3_finalize(statement)
            throw Failure.sqlite(status)
        }
        return statement
    }

    private func rows(_ statement: OpaquePointer?, consume: () throws -> Void) throws {
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try consume()
            case SQLITE_DONE: return
            case let status: throw Failure.sqlite(status)
            }
        }
    }

    private func execute(_ database: OpaquePointer?, _ query: String) throws {
        let status = sqlite3_exec(database, query, nil, nil, nil)
        guard status == SQLITE_OK else { throw Failure.sqlite(status) }
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }
}
