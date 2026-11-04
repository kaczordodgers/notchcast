extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        AgentFleetCommands.list,
        AgentFleetCommands.status,
        AgentFleetCommands.pending,
    ]
}
