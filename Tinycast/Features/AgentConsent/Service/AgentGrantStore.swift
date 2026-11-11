import Foundation

@MainActor
final class AgentGrantStore {
    private let defaults: UserDefaults
    private let key: String
    private(set) var grants: [AgentConsentPolicy.Grant]

    init(bundleIdentifier: String, key: String) throws {
        let suite = NotchcastIdentity(bundleIdentifier: bundleIdentifier).suiteName(suffix: ".notchcast.agent-consent")
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw CocoaError(.fileReadUnknown)
        }
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key) {
            grants = try JSONDecoder().decode([AgentConsentPolicy.Grant].self, from: data)
        } else {
            grants = []
        }
    }

    func allow(agentID: String, actionID: String, danger: AgentConsentPolicy.Danger) throws {
        guard danger == .consent, !agentID.isEmpty, !actionID.isEmpty else { return }
        var updated = grants.filter { !($0.agentID == agentID && $0.actionID == actionID) }
        updated.append(.init(agentID: agentID, actionID: actionID, expiresAt: nil))
        try save(updated)
    }

    private func save(_ updated: [AgentConsentPolicy.Grant]) throws {
        defaults.set(try JSONEncoder().encode(updated), forKey: key)
        grants = updated
    }
}
