extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        ColorPickerModule.launcherCommand,
        ScreenshotModule.launcherCommand,
        MachineSetupProfileCoordinator.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        AgentSessionsModule.refreshCommand,
        PlainPasteModule.launcherCommand,
        FinderToolsCoordinator.cutCommand,
        FinderToolsCoordinator.pasteCommand,
        FinderToolsCoordinator.renameCommand,
    ]
}
