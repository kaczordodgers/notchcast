import Foundation
import Observation
import OSLog

@MainActor @Observable
final class TodoStore {
    nonisolated static let schemaVersion = 1

    private(set) var state: TodoState
    private(set) var replication: TodoReplication
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
        case invalidReplicaID
        case noUndo
        case closed
        case writeFailed
    }

    private struct Record: Codable, Sendable {
        var schemaVersion = TodoStore.schemaVersion
        var command: TodoCommand
        var isUndo: Bool
        var envelope: TodoEnvelope?
        var received: [TodoEnvelope]?
    }

    private struct Loaded: Sendable {
        var replication: TodoReplication
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
        replication = loaded.replication
        state = loaded.replication.state
        inverses = loaded.inverses
        loadWarnings = loaded.warnings
        let url = directory.appending(path: "commands.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let replicaURL = directory.appending(path: "replica-id")
        if !FileManager.default.fileExists(atPath: replicaURL.path) {
            try Data(loaded.replication.replicaID.utf8).write(to: replicaURL, options: .withoutOverwriting)
        }
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
        var candidate = replication
        let inverse = try candidate.perform(command)
        try append(Record(command: command, isUndo: false, envelope: candidate.envelopes.last))
        replication = candidate
        state = candidate.state
        inverses.append(inverse)
        return inverse
    }

    func undo() throws {
        guard let inverse = inverses.last else { throw Failure.noUndo }
        var candidate = replication
        try candidate.perform(inverse)
        try append(Record(command: inverse, isUndo: true, envelope: candidate.envelopes.last))
        replication = candidate
        state = candidate.state
        inverses.removeLast()
    }

    func receive(_ envelopes: [TodoEnvelope]) throws {
        let candidate = try TodoReplication.merge(local: replication, remote: envelopes)
        guard candidate.envelopes != replication.envelopes else { return }
        let received = candidate.envelopes.filter { envelope in
            !replication.envelopes.contains { $0.replicaID == envelope.replicaID && $0.sequence == envelope.sequence }
        }
        try append(Record(command: .batch([]), isUndo: false, received: received))
        replication = candidate
        state = candidate.state
        inverses.removeAll()
    }

    func request(_ request: TodoAgentRequest, now: Date, calendar: Calendar,
                 staleAfterMinutes: Int, makeID: () -> String) throws -> TodoAgentResponse {
        let plan = try TodoAgentAPI.plan(request, state: state, now: now, calendar: calendar,
                                        staleAfterMinutes: staleAfterMinutes, makeID: makeID)
        if case .batch(let commands) = plan.command, !commands.isEmpty { try perform(plan.command) }
        return plan.response
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
        let replicaURL = directory.appending(path: "replica-id")
        let replicaID: String
        if FileManager.default.fileExists(atPath: replicaURL.path) {
            replicaID = try String(contentsOf: replicaURL, encoding: .utf8)
            guard UUID(uuidString: replicaID) != nil else { throw Failure.invalidReplicaID }
        } else {
            replicaID = UUID().uuidString
        }
        var loaded = Loaded(replication: TodoReplication(replicaID: replicaID))
        guard FileManager.default.fileExists(atPath: url.path) else { return loaded }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        var start = data.startIndex
        var line = 1
        for end in data.indices where data[end] == 0x0A {
            try Task.checkCancellation()
            let record: Record
            do {
                record = try decoder.decode(Record.self, from: data[start..<end])
            } catch { throw Failure.corruptLine(line) }
            guard record.schemaVersion == schemaVersion else { throw Failure.unsupportedSchema(record.schemaVersion) }
            if let received = record.received {
                guard record.envelope == nil, !record.isUndo, record.command == .batch([]) else {
                    throw Failure.corruptLine(line)
                }
                do {
                    loaded.replication = try TodoReplication.merge(local: loaded.replication, remote: received)
                } catch { throw Failure.corruptLine(line) }
                loaded.inverses.removeAll()
            } else if record.isUndo {
                guard let inverse = loaded.inverses.last, inverse == record.command else {
                    throw Failure.corruptLine(line)
                }
                do { try loaded.replication.perform(record.command) } catch { throw Failure.corruptLine(line) }
                loaded.inverses.removeLast()
            } else {
                do {
                    loaded.inverses.append(try loaded.replication.perform(record.command))
                } catch { throw Failure.corruptLine(line) }
            }
            if let envelope = record.envelope, loaded.replication.envelopes.last != envelope {
                throw Failure.corruptLine(line)
            }
            start = end + 1
            loaded.validBytes = UInt64(start)
            line += 1
        }
        if start < data.endIndex { loaded.warnings.append(.tornLastLine(line: line)) }
        return loaded
    }
}
