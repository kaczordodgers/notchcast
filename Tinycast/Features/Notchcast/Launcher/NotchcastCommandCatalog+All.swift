extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        MusicCommands.openCurrentPlayerCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
        TodoCommands.addFromClipboard,
        TodoCommands.completeNext,
        TodoCommands.undoLast,
    ]
}
