import Foundation

struct TodoEnvelope: Codable, Equatable, Sendable {
    let replicaID: String
    let sequence: UInt64
    let timestamp: UInt64
    let command: TodoCommand
    let changes: TodoReplicationChanges
}

struct TodoVectorClock: Codable, Equatable, Sendable {
    var sequences: [String: UInt64] = [:]
}

enum TodoReplicationError: Error, Equatable, Sendable {
    case invalidEnvelope
    case conflictingEnvelope(replicaID: String, sequence: UInt64)
    case clockExhausted
}

struct TodoReplication: Sendable {
    let replicaID: String
    private(set) var state = TodoState()
    private(set) var envelopes: [TodoEnvelope] = []
    private var timestamp: UInt64 = 0
    private var sequence: UInt64 = 0

    init(replicaID: String) {
        self.replicaID = replicaID
    }

    var vectorClock: TodoVectorClock {
        var seen: [String: Set<UInt64>] = [:]
        for envelope in envelopes { seen[envelope.replicaID, default: []].insert(envelope.sequence) }
        var result = TodoVectorClock()
        for (replica, sequences) in seen {
            var prefix: UInt64 = 0
            while prefix < UInt64.max, sequences.contains(prefix + 1) { prefix += 1 }
            result.sequences[replica] = prefix
        }
        return result
    }

    func envelopes(after clock: TodoVectorClock) -> [TodoEnvelope] {
        envelopes.filter { $0.sequence > clock.sequences[$0.replicaID, default: 0] }.sorted(by: Self.ordered)
    }

    @discardableResult
    mutating func perform(_ command: TodoCommand) throws -> TodoCommand {
        guard !replicaID.isEmpty else { throw TodoReplicationError.invalidEnvelope }
        guard timestamp < UInt64.max, sequence < UInt64.max else { throw TodoReplicationError.clockExhausted }
        var candidate = state
        let inverse = try candidate.apply(command)
        let changes = TodoReplicationChanges(command: command, before: state, after: candidate)
        timestamp += 1
        sequence += 1
        envelopes.append(TodoEnvelope(replicaID: replicaID, sequence: sequence, timestamp: timestamp,
                                      command: command, changes: changes))
        state = candidate
        return inverse
    }

    static func merge(local: TodoReplication, remote: [TodoEnvelope]) throws -> TodoReplication {
        var result = local
        var records: [String: [UInt64: TodoEnvelope]] = [:]
        for envelope in local.envelopes + remote {
            guard !envelope.replicaID.isEmpty, envelope.sequence > 0,
                  envelope.timestamp >= envelope.sequence else { throw TodoReplicationError.invalidEnvelope }
            if let previous = records[envelope.replicaID]?[envelope.sequence], previous != envelope {
                throw TodoReplicationError.conflictingEnvelope(replicaID: envelope.replicaID, sequence: envelope.sequence)
            }
            records[envelope.replicaID, default: [:]][envelope.sequence] = envelope
        }
        result.envelopes = records.values.flatMap(\.values).sorted(by: ordered)
        var projection = TodoReplicationProjection()
        for envelope in result.envelopes { try projection.apply(envelope.changes) }
        result.state = try projection.state()
        result.timestamp = result.envelopes.map(\.timestamp).max() ?? 0
        result.sequence = records[result.replicaID]?.keys.max() ?? 0
        return result
    }

    private static func ordered(_ lhs: TodoEnvelope, _ rhs: TodoEnvelope) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        if lhs.replicaID != rhs.replicaID { return lhs.replicaID < rhs.replicaID }
        return lhs.sequence < rhs.sequence
    }
}
