enum AgentAnswer: Equatable, Sendable {
    case reply(String)
    case choice(String)
    case approve
    case deny
}
