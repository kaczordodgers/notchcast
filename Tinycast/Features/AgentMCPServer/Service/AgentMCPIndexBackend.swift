import Foundation

@MainActor
struct AgentMCPIndexBackend: AgentMCPBackend {
    let index: AgentActionIndex

    func actions() async throws -> [AgentMCPAction] {
        try await catalog().actions.filter(\.available).map {
            try AgentMCPAction(id: $0.id, title: $0.title, inputSchema: JSONEncoder().encode($0.parameters),
                               danger: $0.danger.rawValue, isDestructive: $0.danger != .harmless)
        }
    }

    func call(_ id: String, arguments: Data) async throws -> Data {
        let parameters: AgentJSON
        do { parameters = try JSONDecoder().decode(AgentJSON.self, from: arguments) } catch {
            throw AgentMCPFailure(code: -32602, message: "Invalid arguments")
        }
        return try await JSONEncoder().encode(result(for: .init(verb: .run, id: id, parameters: parameters)))
    }

    func states() async throws -> [AgentMCPState] {
        try await catalog().states.filter(\.available).map { AgentMCPState(id: $0.id, title: $0.title) }
    }

    func readState(_ id: String) async throws -> Data {
        try await JSONEncoder().encode(result(for: .init(verb: .get, id: id)))
    }

    private func catalog() async throws -> AgentCatalog {
        guard let catalog = try await AgentCatalog(result(for: .init(verb: .list))) else {
            throw AgentMCPFailure(code: -32603, message: "Invalid action catalog")
        }
        return catalog
    }

    private func result(for request: AgentRequest) async throws -> AgentJSON {
        var request = request
        request.isMCP = true
        let reply = await index.handle(request)
        switch reply.code {
        case .ok: return reply.result
        case .declined: throw AgentMCPFailure(code: -32001, message: "Consent refused")
        case .badRequest: throw AgentMCPFailure(code: -32602, message: "Invalid action or arguments")
        case .notRunning: throw AgentMCPFailure(code: -32000, message: "Agent actions stopped")
        case .failed: throw AgentMCPFailure(code: -32603, message: "Action failed")
        }
    }
}
