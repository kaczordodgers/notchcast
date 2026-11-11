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
        try Self.lock.withLock {
            try storedLines().compactMap { try? JSONDecoder().decode(CleanHistoryEntry.self, from: $0) }.reversed()
        }
    }

    /// Rewrites lines as read, so one it cannot decode stays on disk instead of vanishing.
    func append(_ entry: CleanHistoryEntry) throws {
        try Self.lock.withLock {
            var lines = try (storedLines() + [JSONEncoder().encode(entry)]).map { $0 + Data([10]) }
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
            try restore()
            throw error
        }
    }

    private func storedLines() throws -> [Data] {
        guard FileManager().fileExists(atPath: logPath.path) else { return [] }
        return try Data(contentsOf: logPath).split(separator: 10).map { Data($0) }
    }
}
