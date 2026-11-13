import Foundation
import SQLite3

enum CleanQuarantineDatabase {
    static func run(
        _ url: URL, timeout: TimeInterval, clear: Bool,
        beforeTransaction: @Sendable (OpaquePointer?) -> Void = { _ in }
    ) throws -> Int {
        try Task.checkCancellation()
        guard FileManager().fileExists(atPath: url.path) else { return 0 }
        guard url.standardizedFileURL == url.resolvingSymlinksInPath() else {
            throw CocoaError(.fileReadNoPermission)
        }
        var database: OpaquePointer?
        let flags = clear ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &database, flags | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, Int32(min(max(timeout, 0) * 1000, Double(Int32.max))))
        if clear {
            beforeTransaction(database)
            guard sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
                throw CocoaError(.fileWriteUnknown)
            }
            defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }
            try Task.checkCancellation()
            guard sqlite3_exec(database, "DELETE FROM LSQuarantineEvent", nil, nil, nil) == SQLITE_OK,
                  sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM LSQuarantineEvent", -1, &statement, nil) == SQLITE_OK
        else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw CocoaError(.fileReadUnknown) }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
