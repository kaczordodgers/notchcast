extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        BatteryModule.launcherCommand,
        FanControl.maxCommand,
        FanControl.autoCommand,
    ]
}
