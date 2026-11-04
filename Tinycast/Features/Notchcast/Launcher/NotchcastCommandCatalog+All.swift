extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        ForkSettingsBackupCoordinator.restoreCommand,
        ForkSettingsBackupCoordinator.openCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
    ]
}
