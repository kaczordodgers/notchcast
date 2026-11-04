extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        MachineSetupProfileCoordinator.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        BatteryModule.launcherCommand,
        FanControl.maxCommand,
        FanControl.autoCommand,
        PlainPasteModule.launcherCommand,
        FinderToolsCoordinator.cutCommand,
        FinderToolsCoordinator.pasteCommand,
        FinderToolsCoordinator.renameCommand,
    ]
}
