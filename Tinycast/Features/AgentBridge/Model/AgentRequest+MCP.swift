extension AgentRequest {
    var isValidMCP: Bool {
        guard id?.isEmpty == false else { return false }
        if case .string(let line) = parameters { return line.utf8.count <= AgentMCPStdio.lineLimit }
        return parameters == .null
    }
}
