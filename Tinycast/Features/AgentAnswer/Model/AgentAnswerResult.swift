enum AgentAnswerResult: Equatable, Sendable {
    case sent, queued, alreadyAnswered, gone, stale, relink
    case disabled, inProgress, invalidAnswer, cancelled
    case failed(String)
}
