import Foundation

struct AgentRequest: Codable, Equatable, Sendable {
    enum Verb: String, Codable, Sendable {
        case list
        case get
        case run
        case audit
        case status
        case mcp
    }

    let verb: Verb
    var id: String?
    var parameters: AgentJSON = .object([:])
    var dryRun = false
    var isMCP = false
    var keepAlive = false

    private enum CodingKeys: String, CodingKey { case verb, id, parameters, dryRun, keepAlive }

    init(verb: Verb, id: String? = nil, parameters: AgentJSON = .object([:]), dryRun: Bool = false) {
        self.verb = verb
        self.id = id
        self.parameters = parameters
        self.dryRun = dryRun
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verb = try container.decode(Verb.self, forKey: .verb)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        parameters = try container.contains(.parameters) ? container.decode(AgentJSON.self, forKey: .parameters) : .object([:])
        dryRun = try container.contains(.dryRun) ? container.decode(Bool.self, forKey: .dryRun) : false
        keepAlive = try container.decodeIfPresent(Bool.self, forKey: .keepAlive) ?? false
    }

    static func parse(_ arguments: [String]) throws -> (request: Self, json: Bool) {
        var values = arguments
        let json = values.contains("--json")
        values.removeAll { $0 == "--json" }
        let dryRun = values.contains("--dry-run")
        values.removeAll { $0 == "--dry-run" }
        guard let first = values.first, let verb = Verb(rawValue: first) else {
            throw AgentReply.Code.badRequest
        }
        values.removeFirst()
        guard !dryRun || verb == .run else { throw AgentReply.Code.badRequest }
        var request = Self(verb: verb, dryRun: dryRun)
        switch verb {
        case .list, .audit, .status:
            guard values.isEmpty else { throw AgentReply.Code.badRequest }
        case .mcp: guard values.isEmpty else { throw AgentReply.Code.badRequest }
        case .get:
            guard values.count == 1, !values[0].isEmpty else { throw AgentReply.Code.badRequest }
            request.id = values[0]
        case .run:
            guard (1...2).contains(values.count), !values[0].isEmpty else { throw AgentReply.Code.badRequest }
            request.id = values[0]
            if values.count == 2 {
                request.parameters = try JSONDecoder().decode(AgentJSON.self, from: Data(values[1].utf8))
            }
            guard case .object = request.parameters else { throw AgentReply.Code.badRequest }
        }
        return (request, json)
    }

    var isValid: Bool {
        guard !dryRun || verb == .run else { return false }
        switch verb {
        case .list, .audit, .status: return id == nil && parameters == .object([:])
        case .get: return id?.isEmpty == false && parameters == .object([:])
        case .run: return id?.isEmpty == false
        case .mcp: return isValidMCP
        }
    }
}
