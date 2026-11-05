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

    enum Failure: String, Codable, Sendable { case off, failed }
    let rows: [Row]
    let failure: Failure?

    func column(now: Date, remote: Bool) -> Column {
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
