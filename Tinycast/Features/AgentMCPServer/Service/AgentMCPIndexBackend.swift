import Foundation

@MainActor
struct AgentMCPIndexBackend: AgentMCPBackend {
    let index: AgentActionIndex

    func actions() async throws -> [AgentMCPAction] {
        try await catalog("actions").compactMap { fields in
            guard case .string(let id) = fields["id"], case .string(let title) = fields["title"],
                  case .string(let danger) = fields["danger"], let schema = fields["parameters"] else {
                return nil
            }
            return try AgentMCPAction(id: id, title: title, inputSchema: JSONEncoder().encode(schema), danger: danger)
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
        try await catalog("states").compactMap { fields in
            guard case .string(let id) = fields["id"], case .string(let title) = fields["title"] else { return nil }
            return AgentMCPState(id: id, title: title)
        }
    }

    func readState(_ id: String) async throws -> Data {
        try await JSONEncoder().encode(result(for: .init(verb: .get, id: id)))
    }

    private func catalog(_ key: String) async throws -> [[String: AgentJSON]] {
        guard case .object(let catalog) = try await result(for: .init(verb: .list)),
              case .array(let entries) = catalog[key] else {
            throw AgentMCPFailure(code: -32603, message: "Invalid action catalog")
        }
        return entries.compactMap {
            guard case .object(let fields) = $0, fields["available"] == .bool(true) else { return nil }
            return fields
        }
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
