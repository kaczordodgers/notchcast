import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case island, islandExternalDisplays, islandFullScreen, islandHoverOpen
    case islandStatusMessages, islandLiveActivities, launcherFromIsland

    var title: String {
        switch self {
        case .island: String(localized: "Island")
        case .islandExternalDisplays: String(localized: "External displays")
        case .islandFullScreen: String(localized: "Full-screen apps")
        case .islandHoverOpen: String(localized: "Open on hover")
        case .islandStatusMessages: String(localized: "Status messages")
        case .islandLiveActivities: String(localized: "Live activities")
        case .launcherFromIsland: String(localized: "Launcher from island")
        }
    }

    var subtitle: String {
        switch self {
        case .island: String(localized: "Show the island at the top of the screen.")
        case .islandExternalDisplays: String(localized: "Show the island on external displays.")
        case .islandFullScreen: String(localized: "Show the island over full-screen apps.")
        case .islandHoverOpen: String(localized: "Open the island when the pointer hovers over it.")
        case .islandStatusMessages: String(localized: "Show status messages in the island.")
        case .islandLiveActivities: String(localized: "Show live activities in the island.")
        case .launcherFromIsland: String(localized: "Open the launcher from the island.")
        }
    }
}
