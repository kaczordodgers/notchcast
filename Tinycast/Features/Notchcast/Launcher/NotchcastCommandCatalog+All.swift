extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        MachRemoteModule.launcherCommand,
        MachRemoteModule.sendFilesCommand,
        MachRemoteModule.updateCommand,
    ]
}
