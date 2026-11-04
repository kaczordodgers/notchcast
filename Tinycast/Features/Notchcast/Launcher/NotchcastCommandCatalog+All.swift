extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        ColorPickerModule.launcherCommand,
        ScreenshotModule.launcherCommand,
        MachineSetupProfileCoordinator.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        AppearanceCoordinator.launcherCommand,
        PlainPasteModule.launcherCommand,
        FinderToolsCoordinator.cutCommand,
        FinderToolsCoordinator.pasteCommand,
        FinderToolsCoordinator.renameCommand,
    ]
}
