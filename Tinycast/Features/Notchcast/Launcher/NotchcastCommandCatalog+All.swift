extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        MusicCommands.openCurrentPlayerCommand,
        TorrentCommands.downloadClipboardCommand,
        TorrentCommands.openFileCommand,
        TorrentCommands.cancelAllCommand,
    ]
}
