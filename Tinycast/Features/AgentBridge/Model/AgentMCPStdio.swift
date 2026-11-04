import Foundation

enum AgentMCPStdio {
    static let lineLimit = 131_072

    static func run(input: FileHandle, output: FileHandle, send: (AgentRequest) -> AgentReply) throws {
        let session = UUID().uuidString
        defer { _ = send(.init(verb: .mcp, id: session, parameters: .null)) }
        var pending = Data()
        var discarding = false
        while true {
            let chunk = input.availableData
            guard !chunk.isEmpty else { break }
            pending.append(chunk)
            while let end = pending.firstIndex(of: 10) {
                let line = Data(pending[..<end])
                pending.removeSubrange(...end)
                if discarding { discarding = false } else {
                    try exchange(line, session: session, output: output, send: send)
                }
            }
            if discarding { pending.removeAll() }
            if pending.count > lineLimit {
                try output.write(contentsOf: failure(line: Data(), code: .badRequest))
                pending.removeAll()
                discarding = true
            }
        }
        if !pending.isEmpty { try exchange(pending, session: session, output: output, send: send) }
    }

    private static func exchange(_ line: Data, session: String, output: FileHandle,
                                 send: (AgentRequest) -> AgentReply) throws {
        guard line.count <= lineLimit, let text = String(data: line, encoding: .utf8) else {
            try output.write(contentsOf: failure(line: line, code: .badRequest))
            return
        }
        let reply = send(.init(verb: .mcp, id: session, parameters: .string(text)))
        if reply.code == .ok {
            switch reply.result {
            case .string(let response): try output.write(contentsOf: Data(response.utf8))
            case .null: break
            default: try output.write(contentsOf: failure(line: line, code: .failed))
            }
        } else if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["id"] == nil, object["method"] is String {
            return
        } else {
            try output.write(contentsOf: failure(line: line, code: reply.code))
        }
    }

    private static func failure(line: Data, code: AgentReply.Code) throws -> Data {
        let object = (try? JSONDecoder().decode(AgentJSON.self, from: line))
        let id: AgentJSON
        if case .object(let fields) = object { id = fields["id"] ?? .null } else { id = .null }
        let response = AgentJSON.object([
            "jsonrpc": .string("2.0"), "id": id,
            "error": .object(["code": .number(-32000), "message": .string("Agent MCP unavailable: " + code.rawValue)])
        ])
        return try JSONEncoder().encode(response) + Data([10])
    }
}
