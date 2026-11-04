import Foundation

extension AgentRequest {
    func auditEntry(reply: AgentReply, time: Date) -> AgentAuditEntry? {
        guard verb == .run, !dryRun else { return nil }
        let parameters: [String: String]
        if case .object(let fields) = self.parameters {
            parameters = fields.mapValues { _ in "redacted" }
        } else { parameters = [:] }
        return AgentAuditEntry(time: time, agentID: "local-cli", client: isMCP ? "mcp" : "local-cli",
            surface: isMCP ? .mcp : .cli, actionID: id ?? "", parameters: parameters,
            verdict: reply.code == .ok ? .ran : reply.code == .declined ? .declined : .failed,
            succeeded: reply.code == .ok, duration: 0)
    }
}
