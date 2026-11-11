import Foundation
import SQLite3

protocol WaitingAlertsReading: Sendable {
    func read() async throws -> [WaitingAlert]
}

struct WaitingAlertsReader: WaitingAlertsReading {
    var url = AgentPaths(home: FileManager.default.homeDirectoryForCurrentUser).t3State

    @concurrent
    func read() async throws -> [WaitingAlert] {
        try Task.checkCancellation()
        var database: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        defer { sqlite3_close(database) }
        guard status == SQLITE_OK else { throw WaitingAlertsFailure.unavailable }
        guard sqlite3_busy_timeout(database, 500) == SQLITE_OK else { throw WaitingAlertsFailure.unavailable }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = """
            SELECT t.thread_id, t.title,
                   MAX(CASE WHEN r.kind = 'user_input' THEN 0 ELSE 1 END)
            FROM orchestration_v2_projection_runtime_requests r
            JOIN orchestration_v2_projection_threads t ON t.thread_id = r.thread_id
            WHERE r.resolved_at IS NULL AND t.deleted_at IS NULL AND t.archived_at IS NULL
            GROUP BY t.thread_id, t.title
            ORDER BY t.thread_id
            """
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw WaitingAlertsFailure.unavailable
        }
        var waiting: [WaitingAlert] = []
        while true {
            try Task.checkCancellation()
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let id = sqlite3_column_text(statement, 0),
                      let title = sqlite3_column_text(statement, 1) else { throw WaitingAlertsFailure.unavailable }
                waiting.append(WaitingAlert(id: String(cString: id), title: String(cString: title),
                                            kind: sqlite3_column_int(statement, 2) > 0 ? .approval : .question))
            case SQLITE_DONE: return waiting
            default: throw WaitingAlertsFailure.unavailable
            }
        }
    }
}

enum WaitingAlertsFailure: Error { case unavailable }
