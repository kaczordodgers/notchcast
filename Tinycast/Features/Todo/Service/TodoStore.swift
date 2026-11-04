import Foundation
import Observation
import OSLog

@MainActor @Observable
final class TodoStore {
    nonisolated static let schemaVersion = 1

    private(set) var state: TodoState
    let directory: URL
    let loadWarnings: [LoadWarning]
    var canUndo: Bool { !inverses.isEmpty }
    private var inverses: [TodoCommand]
    @ObservationIgnored private let log: FileHandle
    @ObservationIgnored private var writeFailed = false
    @ObservationIgnored private var isClosed = false

    enum LoadWarning: Equatable, Sendable {
        case tornLastLine(line: Int)
    }

    enum Failure: Error, Equatable {
        case unsupportedSchema(Int)
        case corruptLine(Int)
        case noUndo
        case closed
        case writeFailed
    }

    private struct Record: Codable, Sendable {
        var schemaVersion = TodoStore.schemaVersion
        var command: TodoCommand
        var isUndo: Bool
    }

    private struct Loaded: Sendable {
        var state = TodoState()
        var inverses: [TodoCommand] = []
        var warnings: [LoadWarning] = []
        var validBytes: UInt64 = 0
    }

    static func open(directory: URL) async throws -> TodoStore {
        let loaded = try await read(directory: directory)
        try Task.checkCancellation()
        return try TodoStore(directory: directory, loaded: loaded)
    }

    private init(directory: URL, loaded: Loaded) throws {
        self.directory = directory
        state = loaded.state
        inverses = loaded.inverses
        loadWarnings = loaded.warnings
        let url = directory.appending(path: "commands.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data().write(to: url, options: .withoutOverwriting)
        }
        log = try FileHandle(forWritingTo: url)
        if !loaded.warnings.isEmpty { try log.truncate(atOffset: loaded.validBytes) }
        try log.seekToEnd()
    }

    isolated deinit {
        guard !isClosed else { return }
        do { try log.close() } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast", category: "Todo")
                .error("Task log failed to close: \(error)")
        }
    }

    @discardableResult
    func perform(_ command: TodoCommand) throws -> TodoCommand {
        var candidate = state
        let inverse = try candidate.apply(command)
        try append(Record(command: command, isUndo: false))
        state = candidate
        inverses.append(inverse)
        return inverse
    }

    func undo() throws {
        guard let inverse = inverses.last else { throw Failure.noUndo }
        var candidate = state
        try candidate.apply(inverse)
        try append(Record(command: inverse, isUndo: true))
        state = candidate
        inverses.removeLast()
    }

    func close() throws {
        guard !isClosed else { return }
        isClosed = true
        try log.close()
    }

    private func append(_ record: Record) throws {
        guard !isClosed else { throw Failure.closed }
        guard !writeFailed else { throw Failure.writeFailed }
        var data = try JSONEncoder().encode(record)
        data.append(0x0A)
        let offset = try log.offset()
        do {
            try log.write(contentsOf: data)
            try log.synchronize()
        } catch {
            do {
                try log.truncate(atOffset: offset)
                try log.seek(toOffset: offset)
                try log.synchronize()
            } catch {
                writeFailed = true
                throw Failure.writeFailed
            }
            throw error
        }
    }

    @concurrent
    private static func read(directory: URL) async throws -> Loaded {
        let url = directory.appending(path: "commands.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return Loaded() }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        var loaded = Loaded()
        var start = data.startIndex
        var line = 1
        for end in data.indices where data[end] == 0x0A {
            try Task.checkCancellation()
            let record: Record
            do {
                record = try decoder.decode(Record.self, from: data[start..<end])
            } catch { throw Failure.corruptLine(line) }
            guard record.schemaVersion == schemaVersion else { throw Failure.unsupportedSchema(record.schemaVersion) }
            if record.isUndo {
                guard let inverse = loaded.inverses.last, inverse == record.command else {
                    throw Failure.corruptLine(line)
                }
                do { try loaded.state.apply(record.command) } catch { throw Failure.corruptLine(line) }
                loaded.inverses.removeLast()
            } else {
                do {
                    loaded.inverses.append(try loaded.state.apply(record.command))
                } catch { throw Failure.corruptLine(line) }
            }
            start = end + 1
            loaded.validBytes = UInt64(start)
            line += 1
        }
        if start < data.endIndex { loaded.warnings.append(.tornLastLine(line: line)) }
        return loaded
    }
}
