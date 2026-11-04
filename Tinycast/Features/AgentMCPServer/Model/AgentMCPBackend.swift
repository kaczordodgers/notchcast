import Foundation

struct AgentMCPAction: Sendable {
    static let allowedNames = ["agents.list", "agents.send", "agents.wait", "agents.interrupt"]
    let id: String
    let title: String
    let inputSchema: Data
    let danger: String

    var isAllowed: Bool {
        Self.allowedNames.contains(id)
    }
}

struct AgentMCPState: Sendable {
    let id: String
    let title: String
}

@MainActor
protocol AgentMCPBackend {
    func actions() async throws -> [AgentMCPAction]
    func call(_ id: String, arguments: Data) async throws -> Data
    func states() async throws -> [AgentMCPState]
    func readState(_ id: String) async throws -> Data
}
