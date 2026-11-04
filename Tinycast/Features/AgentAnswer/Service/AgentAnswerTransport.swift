@MainActor
protocol AgentAnswerTransport {
    // Check link, identity and revision atomically with delivery; queued counts as accepted.
    func send(_ answer: AgentAnswer, to item: AgentAnswerItem) async throws -> AgentAnswerResult
}
