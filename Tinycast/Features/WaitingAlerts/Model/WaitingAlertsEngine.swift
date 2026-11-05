import Foundation

struct WaitingAlert: Equatable, Sendable {
    enum Kind: Sendable { case approval, question }
    let id: String
    let title: String
    let kind: Kind
}

enum WaitingAlertsEngine {
    static func notices(previous: [WaitingAlert]?, current: [WaitingAlert]) -> [WaitingAlert] {
        guard let previous else { return [] }
        let ids = Set(previous.map(\.id))
        return current.filter { !ids.contains($0.id) }
    }

    static func countMessage(_ count: Int) -> String {
        count == 0 ? String(localized: "No agents are waiting.", table: "Notchcast")
            : String(localized: "\(count) agents are waiting.", table: "Notchcast")
    }

    /// One new wait names its thread; several new waits report the total, so the notice matches the count.
    static func message(_ notices: [WaitingAlert], total: Int) -> String? {
        guard let first = notices.first else { return nil }
        guard notices.count == 1 else { return countMessage(total) }
        switch first.kind {
        case .approval: return String(localized: "\(first.title) is waiting for approval.", table: "Notchcast")
        case .question: return String(localized: "\(first.title) has a question.", table: "Notchcast")
        }
    }
}
