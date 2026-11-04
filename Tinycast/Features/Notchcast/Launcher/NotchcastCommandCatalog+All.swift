extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        MusicCommands.openCurrentPlayerCommand,
        MusicCommands.resumeLastPlayerCommand,
        MusicCommands.speakerOnCommand,
        MusicCommands.speakerOffCommand,
        MicrophoneMuteCommands.muteLauncherCommand,
        MicrophoneMuteCommands.unmuteLauncherCommand,
    ]
}
