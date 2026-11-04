struct AgentIslandAction: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case openApp
        case openAgent(String)
        case openMessage(String)
        case sendMessage(agentID: String, text: String)
        case stopAgent(String)
        case reviewAttention
        case respondApproval(id: String, accepted: Bool)
        case answerPrompt(id: String, answer: String)
        case dismissFailure
    }

    let sourceID: String
    let kind: Kind
}
