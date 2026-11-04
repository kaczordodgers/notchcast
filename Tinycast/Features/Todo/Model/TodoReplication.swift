import Foundation

struct TodoEnvelope: Codable, Equatable, Identifiable, Sendable {
    struct ID: Codable, Hashable, Sendable {
        let replicaID: String
        let sequence: UInt64
    }

    let replicaID: String
    let sequence: UInt64
    let timestamp: UInt64
    let command: TodoCommand
    let changes: TodoReplicationChanges
    var id: ID { ID(replicaID: replicaID, sequence: sequence) }
}

struct TodoVectorClock: Codable, Equatable, Sendable {
    var sequences: [String: UInt64] = [:]
}

enum TodoReplicationError: Error, Equatable, Sendable {
    case invalidEnvelope
    case conflictingEnvelope(replicaID: String, sequence: UInt64)
    case clockExhausted
    case invalidClock
    case timestampAhead(id: TodoEnvelope.ID, timestamp: UInt64, retryAfter: Date)
}

struct TodoReplication: Sendable {
    let replicaID: String
    private(set) var state = TodoState()
    private(set) var envelopes: [TodoEnvelope] = []
    private(set) var deferredEnvelopes: [TodoEnvelope] = []
    private(set) var clockErrors: [TodoReplicationError] = []
    private(set) var orphansRecovered: [TodoOrphanRecovery] = []
    private var records: [TodoEnvelope.ID: TodoEnvelope] = [:]
    private var projection = TodoReplicationProjection()
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
        var changes = TodoReplicationChanges(command: command, before: state, after: candidate)
        changes.markRestorations(projection.latestDeletes)
        let envelope = TodoEnvelope(replicaID: replicaID, sequence: sequence + 1, timestamp: timestamp + 1,
                                    command: command, changes: changes)
        var nextProjection = projection
        try nextProjection.apply(envelope)
        if changes.hasRestorations || !orphansRecovered.isEmpty {
            let materialized = try nextProjection.materialize()
            candidate = materialized.state
            orphansRecovered = materialized.orphans
        }
        timestamp += 1
        sequence += 1
        envelopes.append(envelope)
        records[envelope.id] = envelope
        projection = nextProjection
        state = candidate
        return inverse
    }

    static func merge(local: TodoReplication, remote: [TodoEnvelope], now: Date) throws -> TodoReplication {
        guard now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 >= 0 else {
            throw TodoReplicationError.invalidClock
        }
        var result = local
        let ceiling = min((now.timeIntervalSince1970 + 86_400) * 1_000, Double(UInt64.max / 2))
        var added: [TodoEnvelope] = []
        var deferred: [TodoEnvelope.ID: TodoEnvelope] = [:]
        result.clockErrors = []
        for envelope in local.deferredEnvelopes + remote {
            guard !envelope.replicaID.isEmpty, envelope.sequence > 0,
                  envelope.timestamp >= envelope.sequence else { throw TodoReplicationError.invalidEnvelope }
            if let previous = result.records[envelope.id] ?? deferred[envelope.id], previous != envelope {
                throw TodoReplicationError.conflictingEnvelope(replicaID: envelope.replicaID, sequence: envelope.sequence)
            }
            if result.records[envelope.id] != nil { continue }
            if Double(envelope.timestamp) > ceiling {
                deferred[envelope.id] = envelope
                continue
            }
            result.records[envelope.id] = envelope
            added.append(envelope)
        }
        result.deferredEnvelopes = deferred.values.sorted(by: ordered)
        result.clockErrors = result.deferredEnvelopes.map {
            .timestampAhead(id: $0.id, timestamp: $0.timestamp,
                            retryAfter: Date(timeIntervalSince1970: Double($0.timestamp) / 1_000 - 86_400))
        }
        guard !added.isEmpty else { return result }
        added.sort(by: ordered)
        if let first = added.first, let last = local.envelopes.last, ordered(first, last) {
            result.envelopes = (local.envelopes + added).sorted(by: ordered)
            result.projection = TodoReplicationProjection()
            for envelope in result.envelopes { try result.projection.apply(envelope) }
        } else {
            result.envelopes.append(contentsOf: added)
            for envelope in added { try result.projection.apply(envelope) }
        }
        let materialized = try result.projection.materialize()
        result.state = materialized.state
        result.orphansRecovered = materialized.orphans
        result.timestamp = max(local.timestamp, added.map(\.timestamp).max() ?? 0)
        result.sequence = max(local.sequence, added.filter { $0.replicaID == result.replicaID }.map(\.sequence).max() ?? 0)
        return result
    }

    private static func ordered(_ lhs: TodoEnvelope, _ rhs: TodoEnvelope) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        if lhs.replicaID != rhs.replicaID { return lhs.replicaID < rhs.replicaID }
        return lhs.sequence < rhs.sequence
    }
}
