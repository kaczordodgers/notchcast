extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        MachineSetupProfileCoordinator.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        AgentSessionsModule.refreshCommand,
        AgentFleetCommands.list,
        AgentFleetCommands.status,
        AgentFleetCommands.pending,
    ]
}
