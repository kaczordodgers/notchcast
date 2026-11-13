import Foundation

struct FleetSnapshot: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case waiting, working, finished }
    struct Row: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let project: String
        let model: String
        let phase: Phase
        let pendingCount: Int
        let link: URL
        let updatedAt: Date

        func updatedAgo(now: Date) -> TimeInterval { max(0, now.timeIntervalSince(updatedAt)) }
    }

    enum Column: Equatable, Sendable {
        case rows([Row])
        case sourceOff
        case linkDown
        case remoteOff
        case failed

        var waiting: Int { rows.filter { $0.phase == .waiting }.count }
        var working: Int { rows.filter { $0.phase == .working }.count }
        private var rows: [Row] { if case let .rows(rows) = self { rows } else { [] } }
    }

    enum Failure: String, Codable, Sendable { case off, sourceOff, failed }
    let rows: [Row]
    let failure: Failure?

    private enum CodingKeys: String, CodingKey { case rows, failure, reason }

    init(rows: [Row], failure: Failure?) {
        self.rows = rows
        self.failure = failure
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rows = try values.decode([Row].self, forKey: .rows)
        let wireFailure = try values.decodeIfPresent(Failure.self, forKey: .failure)
        let reason = try values.decodeIfPresent(String.self, forKey: .reason)
        failure = wireFailure == .off && reason == "sourceOff" ? .sourceOff : wireFailure
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(rows, forKey: .rows)
        try values.encodeIfPresent(failure == .sourceOff ? .off : failure, forKey: .failure)
        if failure == .sourceOff { try values.encode("sourceOff", forKey: .reason) }
    }

    func column(now: Date, remote: Bool) -> Column {
        if failure == .sourceOff { return .sourceOff }
        if let failure { return failure == .off ? (remote ? .remoteOff : .sourceOff) : .failed }
        let rank: [Phase: Int] = [.waiting: 0, .working: 1, .finished: 2]
        return .rows(rows.filter { $0.phase != .finished || now.timeIntervalSince($0.updatedAt) <= 1800 }
            .sorted {
                if $0.phase != $1.phase { return rank[$0.phase, default: 2] < rank[$1.phase, default: 2] }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id < $1.id
            })
    }
}
