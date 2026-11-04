extension NotchcastFeature {
    enum SettingsGroup: Sendable {
        // Keep group appends away from the enum header during union merges.
        case island
        case islandOptions
        case launcher
        case system
        case activities
        case systemTools
        case clean
        case tools
        case tweaks
        case music
        case tasks
        case torrents
        case archives
        case clipboard
        case appearance
        case finder
        case captureAndDictation
        case buildStats
        case agentPricing
        // Keep group appends away from the closing braces during union merges.
    }
}
