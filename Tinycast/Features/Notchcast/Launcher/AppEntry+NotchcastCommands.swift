extension Array where Element == AppEntry {
    func appendingNotchcastCommands() -> [AppEntry] {
        self + NotchcastCommandCatalog.entries
    }
}
