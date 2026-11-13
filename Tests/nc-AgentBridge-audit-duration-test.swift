// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/UI/AgentRequest+Audit.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Service/*.swift
import Foundation

@main
@MainActor
struct AgentAuditDurationTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AgentAuditStore(directory: directory)
        let index = AgentActionIndex()
        for fail in [false, true] {
            let action = AgentAction(id: fail ? "fixture.failure" : "fixture.success", title: "Timed", danger: .harmless)
            try index.register(.init(action: action, run: { _ in
                let deadline = ContinuousClock.now + .milliseconds(10)
                while ContinuousClock.now < deadline { await Task.yield() }
                if fail { throw AgentReply.Code.failed }
                return .null
            }))
        }
        index.didComplete = { request, reply in
            guard let entry = request.auditEntry(reply: reply, time: Date()) else { return }
            do { try await store.append(entry) } catch { preconditionFailure("Audit write failed: \(error)") }
        }
        index.start()
        let success = await index.handle(.init(verb: .run, id: "fixture.success"))
        let failure = await index.handle(.init(verb: .run, id: "fixture.failure"))
        precondition(success.code == .ok && failure.code == .failed)
        let entries = try await store.entries()
        precondition(entries.count == 2)
        precondition(entries.map(\.verdict) == [.ran, .failed])
        precondition(entries.allSatisfy { $0.duration >= 0.01 }, "Audit duration lost elapsed action time")
        print("PASS: success and failure audit entries persist actual elapsed action time")
    }
}
