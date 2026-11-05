import Foundation

struct WaitingAlert: Equatable, Sendable {
    enum Kind: Sendable { case approval, question }
    let id: String
    let title: String
    let kind: Kind
}

enum WaitingAlertsEngine {
    static func waiting(in threads: [AgentThread]) -> [WaitingAlert] {
        threads.compactMap { thread in
            guard thread.phase.waiting else { return nil }
            return WaitingAlert(id: thread.id, title: thread.title,
                                kind: thread.phase == .waitingForApproval ? .approval : .question)
        }
    }

    static func notices(previous: [WaitingAlert]?, current: [WaitingAlert]) -> [WaitingAlert] {
        guard let previous else { return [] }
        let ids = Set(previous.map(\.id))
        return current.filter { !ids.contains($0.id) }
    }

    static func countMessage(_ count: Int) -> String {
        count == 0 ? String(localized: "No agents are waiting.")
            : String(localized: "\(count) agents are waiting.")
    }

    static func message(_ notices: [WaitingAlert]) -> String? {
        guard let first = notices.first else { return nil }
        guard notices.count == 1 else { return countMessage(notices.count) }
        switch first.kind {
        case .approval: return String(localized: "\(first.title) is waiting for approval.")
        case .question: return String(localized: "\(first.title) has a question.")
        }
    }
}
