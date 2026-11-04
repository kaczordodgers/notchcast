import Darwin
import Foundation

final class CleanHistoryStore: Sendable {
    let logPath: URL
    let maximumBytes: Int
    private static let lock = NSLock()

    init(logPath: URL, maximumBytes: Int = 1_048_576) {
        self.logPath = logPath
        self.maximumBytes = max(1, maximumBytes)
    }

    func read() throws -> [CleanHistoryEntry] {
        try Self.lock.withLock { try load().reversed() }
    }

    func append(_ entry: CleanHistoryEntry) throws {
        try Self.lock.withLock {
            let encoder = JSONEncoder()
            var lines = try (load() + [entry]).map { try encoder.encode($0) + Data([10]) }
            guard let last = lines.last, last.count <= maximumBytes else {
                throw CleanHistoryError.recordTooLarge
            }
            var count = lines.reduce(0) { $0 + $1.count }
            while count > maximumBytes { count -= lines.removeFirst().count }
            try lines.reduce(into: Data()) { $0.append($1) }.write(to: logPath, options: .atomic)
        }
    }

    func recordTrash(_ entry: CleanHistoryEntry, restore: () throws -> Void) throws {
        do { try append(entry) }
        catch {
            let historyError = error
            do { try restore() }
            catch {
                throw RecoveryFailure(entry: entry, historyError: historyError, restoreError: error)
            }
            throw error
        }
    }

    struct RecoveryFailure: LocalizedError {
        let entry: CleanHistoryEntry
        let historyError: Error
        let restoreError: Error

        var errorDescription: String? {
            "\(entry.originalPath) → \(entry.trashPath): "
                + "\(historyError.localizedDescription); \(restoreError.localizedDescription)"
        }
    }

    private func load() throws -> [CleanHistoryEntry] {
        guard FileManager().fileExists(atPath: logPath.path) else { return [] }
        return try Data(contentsOf: logPath).split(separator: 10).compactMap {
            try? JSONDecoder().decode(CleanHistoryEntry.self, from: Data($0))
        }
    }
}
