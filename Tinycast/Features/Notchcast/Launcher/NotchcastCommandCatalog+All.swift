extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        MusicCommands.openCurrentPlayerCommand,
        TodoCommands.addFromClipboard,
        TodoCommands.completeNext,
        TodoCommands.undoLast,
    ]
}
