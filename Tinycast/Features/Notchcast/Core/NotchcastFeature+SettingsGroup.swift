extension NotchcastFeature {
    enum SettingsGroup: Sendable {
        // Keep group appends away from the enum header during union merges.
        case island
        case islandOptions
        case launcher
        case system
        case activities
        case systemTools
        case clipboard
        case finder
        case buildStats
        // Keep group appends away from the closing braces during union merges.
    }
}
