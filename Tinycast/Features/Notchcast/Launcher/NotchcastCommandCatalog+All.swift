extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        MachineSetupProfileCoordinator.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        MachRemoteModule.launcherCommand,
        MachRemoteModule.sendFilesCommand,
        MachRemoteModule.updateCommand,
        PlainPasteModule.launcherCommand,
        FinderToolsCoordinator.cutCommand,
        FinderToolsCoordinator.pasteCommand,
        FinderToolsCoordinator.renameCommand,
    ]
}
