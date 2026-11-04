// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoStore.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoAgentGateway.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Service/AgentGrantStore.swift
// notchcast-sources: Tinycast/Features/AgentConfirm/Model/*.swift
import Foundation

@main @MainActor
struct TodoAgentsTests {
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "app.notchcast.tests." + UUID().uuidString
        defer { UserDefaults.standard.removePersistentDomain(forName: suite + ".notchcast.agent-consent") }
        let store = try await TodoStore.open(directory: root, now: now)
        let grants = try AgentGrantStore(bundleIdentifier: suite)
        let id = UUID().uuidString
        let sectionID = UUID().uuidString
        let projectID = UUID().uuidString
        try store.perform(.addProject(TodoProject(id: projectID, name: "Test")))
        try store.perform(.addSection(TodoSection(id: sectionID, name: "In progress", projectID: projectID)))
        try store.perform(.addTask(TodoTask(id: id, title: "Test", description: "secret body", projectID: projectID)))
        var records: [TodoAgentGateway.Audit] = []
        var choice = AgentConfirmationEngine.Choice.deny
        var revoke = false
        let gateway = TodoAgentGateway(store: store, grants: grants, clock: { now },
            requiresConfirmation: { _ in true }, confirm: { _ in
                if revoke { try? grants.revoke(agentID: "agent") }
                return choice
            }, audit: { records.append($0) })
        func run(_ request: TodoAgentRequest) throws -> TodoAgentResponse {
            try gateway.request(request, agent: "agent", calendar: Calendar(identifier: .gregorian),
                                staleAfterMinutes: 30, makeID: { UUID().uuidString })
        }
        func expect(_ request: TodoAgentRequest, _ failure: TodoAgentGateway.Failure) throws {
            let before = store.state
            let count = records.count
            do { _ = try run(request); preconditionFailure("Expected denial") } catch {
                precondition(error as? TodoAgentGateway.Failure == failure)
            }
            precondition(store.state == before && records.count == count + 1)
        }
        let requests: [TodoAgentRequest] = [.list(query: nil, sectionID: nil),
            .claim(taskID: id, agent: "agent"), .comment(taskID: id, agent: "agent", text: "secret comment"),
            .move(taskID: id, agent: "agent", sectionID: sectionID), .release(taskID: id, agent: "agent"),
            .complete(taskID: id, agent: "agent"), .releaseExpired]
        for request in requests {
            try expect(request, .denied)
            let action = TodoAgentGateway.actionID(for: request)
            try grants.allow(agentID: "agent", actionID: action, danger: .consent, now: now)
            if case .list = request { _ = try run(request) } else { try expect(request, .declined) }
            try grants.revoke(agentID: "agent", actionID: action)
            try expect(request, .denied)
        }
        for request in requests {
            try grants.allow(agentID: "agent", actionID: TodoAgentGateway.actionID(for: request), danger: .consent, now: now)
        }
        choice = .allowOnce
        for request in requests { _ = try run(request) }
        precondition(records.contains { $0.taskIDs == [id] && $0.result == .succeeded })
        try expect(.comment(taskID: id, agent: "other", text: "secret"), .invalidAgent)
        revoke = true
        try expect(.releaseExpired, .denied)
        revoke = false
        let read = TodoAgentRequest.list(query: nil, sectionID: nil)
        try grants.allow(agentID: "agent", actionID: TodoAgentGateway.actionID(for: read), danger: .consent, now: now)
        let count = records.count
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { @MainActor in _ = try run(read) } }
            try await group.waitForAll()
        }
        precondition(records.count == count + 20)
        try store.close()
        print("PASS: Todo agents grants, revoke, confirmation, audit, unchanged denials, concurrent requests")
    }
}
