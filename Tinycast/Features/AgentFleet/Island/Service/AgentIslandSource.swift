@MainActor
protocol AgentIslandSource {
    var snapshot: AgentIslandState.Snapshot { get }
}
