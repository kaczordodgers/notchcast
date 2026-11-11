import Foundation

enum AgentConsentPolicy {
    enum Danger: String, Codable, Sendable {
        case harmless, consent, dangerous
    }

    enum Decision: Equatable, Sendable {
        case allow, ask, refuse
    }

    struct Grant: Codable, Equatable, Sendable {
        let agentID: String
        let actionID: String
        let expiresAt: Date?

        func covers(agentID: String, actionID: String, now: Date) -> Bool {
            self.agentID == agentID && self.actionID == actionID
                && (expiresAt.map { now < $0 } ?? true)
        }
    }

    static func decide(
        agentID: String, actionID: String, danger: Danger, grants: [Grant], now: Date
    ) -> Decision {
        guard !agentID.isEmpty, !actionID.isEmpty else { return .refuse }
        switch danger {
        case .harmless: return .allow
        case .dangerous: return .refuse
        case .consent:
            return grants.contains { $0.covers(agentID: agentID, actionID: actionID, now: now) }
                ? .allow : .ask
        }
    }
}
