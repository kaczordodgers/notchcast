import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case island, islandExternalDisplays, islandFullScreen, islandHoverOpen
    case islandStatusMessages, islandLiveActivities, launcherFromIsland
    case lowDiskWarning
    case systemNotices
    case volumeLevels
    case displayBrightness
    case quitProtection
    case liveTimers
    case dayCalendar
    case dayWeather
    case dayMarkets
    case agentActions
    case agentCLI

    var title: String {
        switch self {
        case .island: String(localized: "Island")
        case .islandExternalDisplays: String(localized: "External Displays")
        case .islandFullScreen: String(localized: "Full-Screen Apps")
        case .islandHoverOpen: String(localized: "Open on Hover")
        case .islandStatusMessages: String(localized: "Status Messages")
        case .islandLiveActivities: String(localized: "Live Activities")
        case .launcherFromIsland: String(localized: "Launcher from Island")
        case .lowDiskWarning: String(localized: "Low Disk Warning")
        case .systemNotices: String(localized: "System Notices")
        case .volumeLevels: String(localized: "Volume in Island")
        case .displayBrightness: String(localized: "Display Brightness")
        case .quitProtection: String(localized: "Quit Protection")
        case .liveTimers: String(localized: "Timers")
        case .dayCalendar: String(localized: "Calendar")
        case .dayWeather: String(localized: "Weather")
        case .dayMarkets: String(localized: "Markets")
        case .agentActions: String(localized: "Agent access")
        case .agentCLI: String(localized: "Command line tool")
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
        case .lowDiskWarning: String(localized: "Warns below \(10)% or \(30) GB free.")
        case .systemNotices: String(localized: "Wi-Fi, Tailscale and low battery notices in the island.")
        case .volumeLevels: String(localized: "Replaces the macOS volume overlay.")
        case .displayBrightness: String(localized: "Brightness keys control every display, external ones too.")
        case .quitProtection: String(localized: "Stops an app from quitting on a single slip.")
        case .liveTimers: String(localized: "Countdowns and alarms in the island.")
        case .dayCalendar: String(localized: "Calendar events on the Day page.")
        case .dayWeather: String(localized: "Forecast from Open-Meteo on the Day page.")
        case .dayMarkets: String(localized: "Prices refresh every 3 minutes while Day is open.")
        case .agentActions: String(localized: "Expose actions and read-only state to local agents.")
        case .agentCLI: String(localized: "Accept local commands over a private Unix socket.")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        switch self {
        case .volumeLevels, .displayBrightness, .quitProtection: [.accessibility]
        case .island, .islandExternalDisplays, .islandFullScreen, .islandHoverOpen,
            .islandStatusMessages, .islandLiveActivities, .launcherFromIsland,
            .lowDiskWarning, .systemNotices, .liveTimers, .dayCalendar, .dayWeather, .dayMarkets,
            .agentActions, .agentCLI:
            []
        }
    }
}

extension NotchcastFeature {
    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        ![.displayBrightness, .quitProtection, .agentActions, .agentCLI].contains(self)
    }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
}
