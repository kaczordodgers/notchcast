// notchcast-sources: Tinycast/Features/Clean/Service/CleanQuarantineDatabase.swift
import Foundation
import SQLite3

@main
struct CleanDatabaseTest {
    static func main() async throws {
        let manager = FileManager()
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let url = root.resolvingSymlinksInPath().appendingPathComponent("quarantine.db")
        var connection: OpaquePointer?
        precondition(sqlite3_open(url.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        precondition(sqlite3_exec(connection,
            "CREATE TABLE LSQuarantineEvent (id INTEGER); INSERT INTO LSQuarantineEvent VALUES (1), (2)",
            nil, nil, nil) == SQLITE_OK)
        precondition(sqlite3_exec(connection, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        let entered = DispatchSemaphore(value: 0)
        let task = Task.detached {
            try CleanQuarantineDatabase.run(url, timeout: 5, clear: true) { entered.signal() }
        }
        precondition(entered.wait(timeout: .now() + 5) == .success)
        task.cancel()
        precondition(sqlite3_exec(connection, "COMMIT", nil, nil, nil) == SQLITE_OK)
        do {
            _ = try await task.value
            preconditionFailure("Cancelled transaction deleted quarantine rows")
        } catch is CancellationError {}
        let count = try CleanQuarantineDatabase.run(url, timeout: 1, clear: false)
        precondition(count == 2, "Cancelled transaction must preserve every row")
        let remaining = try CleanQuarantineDatabase.run(url, timeout: 1, clear: true)
        precondition(remaining == 0)
        print("PASS: cancellation after lock acquisition preserves rows; uncancelled clear commits")
    }
}
