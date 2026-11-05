import Foundation

struct TodoLinkPacket: Codable, Equatable, Sendable {
    static let maximumBytes = 40_000

    let clock: TodoVectorClock
    let envelopes: [TodoEnvelope]
    let hasMore: Bool

    enum Failure: Error { case tooLarge, unavailable, noProgress }

    static func make(from replication: TodoReplication, after clock: TodoVectorClock) throws -> Self {
        let missing = replication.envelopes(after: clock)
        let known = replication.vectorClock
        let encoder = JSONEncoder()
        let empty = Self(clock: known, envelopes: [], hasMore: false)
        var bytes = try encoder.encode(empty).count
        guard bytes <= maximumBytes else { throw Failure.tooLarge }
        var selected: [TodoEnvelope] = []
        for envelope in missing {
            let size = try encoder.encode(envelope).count + 1
            guard bytes + size <= maximumBytes else { break }
            selected.append(envelope)
            bytes += size
        }
        guard missing.isEmpty || !selected.isEmpty else { throw Failure.tooLarge }
        return Self(clock: known, envelopes: selected, hasMore: selected.count < missing.count)
    }
}
