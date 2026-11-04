extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        MachineSetupProfileCoordinator.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        LiveTimerModule.startCommand,
        LiveTimerModule.stopCommand,
        DayCommands.weather,
        DayCommands.markets,
        DayCommands.calendar,
        LowDiskModule.refreshCommand,
        SystemNoticesModule.refreshCommand,
        QuitProtectionModule.settingsCommand,
        DisplayBrightnessCommands.settings,
        AppearanceCommands.settings,
        SystemLevelsCommands.presets[0],
        SystemLevelsCommands.presets[1],
        SystemLevelsCommands.presets[2],
        SystemLevelsCommands.presets[3],
        SystemLevelsCommands.presets[4],
    ]
}
