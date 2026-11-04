extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        ForkSettingsBackupCoordinator.restoreCommand,
        ForkSettingsBackupCoordinator.openCommand,
        MachineSetupProfileCoordinator.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        PlainPasteModule.launcherCommand,
        FinderToolsCoordinator.cutCommand,
        FinderToolsCoordinator.pasteCommand,
        FinderToolsCoordinator.renameCommand,
    ]
}
