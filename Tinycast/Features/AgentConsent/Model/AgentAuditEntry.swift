import Foundation

struct AgentAuditEntry: Codable, Equatable, Sendable {
    enum Surface: String, Codable, Sendable {
        case deeplink, cli, mcp
    }

    enum Verdict: String, Codable, Sendable {
        case ran, allowedAfterAsking, declined, refused, failed
    }

    let time: Date
    let agentID: String
    let client: String
    let surface: Surface
    let actionID: String
    let parameters: [String: String]
    let verdict: Verdict
    let resultCode: String
    let duration: TimeInterval

    init(
        time: Date, agentID: String, client: String, surface: Surface, actionID: String,
        parameters: [String: String], verdict: Verdict, succeeded: Bool, duration: TimeInterval
    ) {
        self.time = time
        self.agentID = String(agentID.prefix(256))
        self.client = String(client.prefix(256))
        self.surface = surface
        self.actionID = String(actionID.prefix(256))
        // Values and caller-controlled keys can both contain private text.
        self.parameters = parameters.isEmpty ? [:] : ["redacted": String(parameters.count)]
        self.verdict = verdict
        resultCode = succeeded ? "success" : "failure"
        self.duration = duration.isFinite ? max(0, duration) : 0
    }
}
