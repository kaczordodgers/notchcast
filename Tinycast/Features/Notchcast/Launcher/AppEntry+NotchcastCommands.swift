extension Array where Element == AppEntry {
    func appendingNotchcastCommands() -> [AppEntry] {
        map(\.notchcastBranded) + NotchcastCommandCatalog.entries
    }
}

extension AppEntry {
    /// The old name stays an alternate title, so a search typed from Tinycast habit still lands.
    fileprivate var notchcastBranded: AppEntry {
        let branded: String
        switch CommandID(rawValue: id) {
        case .settings: branded = String(localized: "Notchcast Settings", table: "Notchcast")
        case .about: branded = String(localized: "About Notchcast", table: "Notchcast")
        case .quit: branded = String(localized: "Quit Notchcast", table: "Notchcast")
        default: return self
        }
        return AppEntry(
            id: id, name: branded, url: url, bundleID: bundleID, kind: kind,
            settingsOwner: settingsOwner, subtitle: subtitle,
            alternateTitles: alternateTitles + [name], symbolName: symbolName)
    }
}
