import Foundation

@main
struct AgentConsentTests {
    @MainActor
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 100)
        let identifier = "test.agent-consent." + UUID().uuidString
        let store = try AgentGrantStore(bundleIdentifier: identifier)
        defer {
            UserDefaults(suiteName: identifier + ".notchcast.agent-consent")?
                .removePersistentDomain(forName: identifier + ".notchcast.agent-consent")
        }
        func decision(_ agent: String, _ action: String, _ danger: AgentConsentPolicy.Danger) -> AgentConsentPolicy.Decision {
            AgentConsentPolicy.decide(agentID: agent, actionID: action, danger: danger, grants: store.grants, now: now)
        }
        assert(decision("a", "read", .harmless) == .allow)
        assert(decision("a", "write", .consent) == .ask)
        try store.allow(agentID: "a", actionID: "write", danger: .consent)
        assert(decision("a", "write", .consent) == .allow)
        assert(decision("b", "write", .consent) == .ask)
        assert(decision("a", "other", .consent) == .ask)
        let expiring = AgentConsentPolicy.Grant(agentID: "a", actionID: "write", expiresAt: now.addingTimeInterval(10))
        assert(expiring.covers(agentID: "a", actionID: "write", now: now))
        assert(!expiring.covers(agentID: "a", actionID: "write", now: now.addingTimeInterval(10)))
        assert(decision("a", "write", .dangerous) == .refuse)
        let restored = try AgentGrantStore(bundleIdentifier: identifier)
        assert(restored.grants == store.grants)
        try store.allow(agentID: "a", actionID: "kill", danger: .dangerous)
        assert(store.grants.count == 1)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audit = AgentAuditStore(directory: directory, maximumBytes: 1024)
        let entry = AgentAuditEntry(time: now, agentID: "a", client: "test", surface: .cli,
                                   actionID: "write", parameters: ["private note": "secret"],
                                   verdict: .ran, succeeded: true, duration: 0.5)
        for _ in 0..<20 { try await audit.append(entry) }
        let entries = try await audit.entries()
        assert(!entries.isEmpty && entries.count < 20)
        assert(entries.allSatisfy { $0 == entry })
        for name in ["audit.jsonl", "audit.previous.jsonl"] {
            let url = directory.appendingPathComponent(name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            assert((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            assert((attributes[.size] as? NSNumber)!.intValue <= 1024)
            let text = try String(contentsOf: url, encoding: .utf8)
            assert(!text.contains("secret") && !text.contains("private note"))
        }
        let current = directory.appendingPathComponent("audit.jsonl")
        var damaged = try Data(contentsOf: current)
        damaged.append(contentsOf: "{broken}\n".utf8)
        damaged.append(try JSONEncoder().encode(entry))
        damaged.append(0x0A)
        damaged.append(contentsOf: [0xFF, 0x0A])
        try damaged.write(to: current)
        let recovered = try await audit.entries()
        assert(recovered == entries + [entry])
        let cancelledAudit = AgentAuditStore(directory: directory.appendingPathComponent("cancelled"))
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await cancelledAudit.append(entry)
        }
        do {
            try await cancelled.value
        } catch {
            preconditionFailure("Cancelled caller must retain its final audit record: \(error)")
        }
        let cancelledEntries = try await cancelledAudit.entries()
        precondition(cancelledEntries == [entry])
        print("PASS: cancelled caller's audit append persisted exactly once")
        print("PASS: consent, audit redaction/rotation/0600; two bad lines skipped, valid tail retained")
    }
}
