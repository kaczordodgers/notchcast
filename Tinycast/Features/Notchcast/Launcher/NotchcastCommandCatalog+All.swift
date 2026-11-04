extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        MusicCommands.openCurrentPlayerCommand,
        MusicCommands.resumeLastPlayerCommand,
        MusicCommands.speakerOnCommand,
        MusicCommands.speakerOffCommand,
        MicrophoneMuteCommands.muteLauncherCommand,
        MicrophoneMuteCommands.unmuteLauncherCommand,
    ]
}
