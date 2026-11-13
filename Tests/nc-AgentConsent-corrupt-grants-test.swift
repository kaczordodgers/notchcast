import Foundation

@main
struct CorruptGrantsTests {
    @MainActor
    static func main() throws {
        let identifier = "test.corrupt-grants." + UUID().uuidString
        let suite = NotchcastIdentity(bundleIdentifier: identifier).suiteName(suffix: ".notchcast.agent-consent")
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "agentActionGrants"
        defaults.set(Data("{broken".utf8), forKey: key)
        let recovered = try AgentGrantStore(bundleIdentifier: identifier, key: key)
        precondition(recovered.grants.isEmpty)
        precondition(defaults.data(forKey: key) == nil)
        let relaunched = try AgentGrantStore(bundleIdentifier: identifier, key: key)
        precondition(relaunched.grants.isEmpty)
        precondition(AgentConsentPolicy.decide(agentID: "a", actionID: "write", danger: .consent,
            grants: relaunched.grants, now: Date()) == .ask)
        try relaunched.allow(agentID: "a", actionID: "write", danger: .consent)
        let saved = try AgentGrantStore(bundleIdentifier: identifier, key: key)
        precondition(saved.grants.count == 1)
        print("PASS: corrupt grants reset without granting consent; relaunch and new grants work")
    }
}
