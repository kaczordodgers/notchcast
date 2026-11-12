import Foundation

nonisolated struct AIUsageSnapshot: Sendable, Equatable {
    enum Status: Sendable {
        case available, stale
    }

    struct Window: Sendable, Equatable {
        let id: String
        let label: String
        let used: Double
        let limit: Double
        let resetsAt: Date?

        var percentLeft: Int {
            guard limit > 0 else { return 0 }
            return Int((100 - min(100, max(0, used / limit * 100))).rounded())
        }

        func percentLeft(at now: Date, readAt: Date?) -> Int {
            if let readAt, let resetsAt, readAt < resetsAt, resetsAt <= now { return 100 }
            return percentLeft
        }

        func secondsUntilReset(at now: Date) -> TimeInterval? {
            guard let resetsAt, resetsAt > now else { return nil }
            return max(1, resetsAt.timeIntervalSince(now).rounded(.up))
        }
    }

    let providerID: String
    let plan: String?
    let checkedAt: Date?
    let status: Status
    let windows: [Window]
    var accountID: String = ""
    var accountName: String = ""
    var asOf: Date?
}
