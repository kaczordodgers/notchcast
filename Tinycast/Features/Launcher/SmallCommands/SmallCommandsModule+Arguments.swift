extension SmallCommandsModule {
    /// Alias Space focuses a command's inline field instead of running it with nothing typed.
    nonisolated static func argumentCount(entryID: String) -> Int {
        entryID == shortenCommand.id ? 1 : 0
    }
}
