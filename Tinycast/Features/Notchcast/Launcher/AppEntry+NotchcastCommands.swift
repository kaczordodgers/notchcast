extension Array where Element == AppEntry {
    func appendingNotchcastCommands(ownedBy owner: SettingsTab? = nil) -> [AppEntry] {
        self + NotchcastCommandCatalog.entries.filter { owner == nil || $0.settingsOwner == owner }
    }
}
