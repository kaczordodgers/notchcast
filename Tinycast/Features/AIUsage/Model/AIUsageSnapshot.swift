import Foundation

nonisolated struct AIUsageSnapshot: Sendable, Equatable {
    enum Status: Sendable {
        case available, noData, stale, unreadable
    }

    struct Window: Sendable, Equatable {
        let id: String
        let label: String
        let used: Double
        let limit: Double
        let resetsAt: Date?
        let durationMinutes: Double?

        func secondsUntilReset(at now: Date) -> TimeInterval? {
            resetsAt.map { max(0, $0.timeIntervalSince(now)) }
        }
    }

    struct ResetCredits: Decodable, Sendable, Equatable {
        let availableCount: Int
    }

    let providerID: String
    let plan: String?
    let checkedAt: Date?
    let status: Status
    let windows: [Window]
    var resetCredits: ResetCredits?
}
