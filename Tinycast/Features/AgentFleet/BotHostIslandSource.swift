extension BotHostModule: AgentIslandSource {
    var snapshot: AgentIslandState.Snapshot {
        guard enabled else { return .init(sourceID: "bots") }
        guard isConfigured else { return .init(sourceID: "bots", failureID: "Bot host unavailable") }
        return .init(sourceID: "bots", running: states.filter { $0.value == .working }.map(\.key),
            questions: pendingCounts.values.reduce(0, +),
            failureID: states.values.contains(.failed) ? "Bot failed" : nil)
    }
}
