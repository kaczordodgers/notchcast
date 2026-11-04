import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case t3Threads
    case waitingAlerts
    case fleetPanel
    case agentIsland
    case botHost
    case island
    case islandExternalDisplays
    case islandFullScreen
    case islandHoverOpen
    case islandStatusMessages
    case islandLiveActivities
    case launcherFromIsland
    case systemMonitor
    case fanControl
    case monitorAlerts
    case lowDiskWarning
    case systemNotices
    case volumeLevels
    case displayBrightness
    case quitProtection
    case liveTimers
    case dayCalendar
    case dayWeather
    case dayMarkets
    case batteryChargeLimit
    case batterySailing
    case batteryHeatProtection
    case batteryCalibration
    case keepAwake
    case lidClosedAwake
    case linkQuickFixes

    var settingsGroup: SettingsGroup {
        switch self {
        case .t3Threads: .activities
        case .waitingAlerts: .activities
        case .fleetPanel: .activities
        case .agentIsland: .activities
        case .botHost: .activities
        case .island: .island
        case .islandExternalDisplays: .islandOptions
        case .islandFullScreen: .islandOptions
        case .islandHoverOpen: .islandOptions
        case .islandStatusMessages: .islandOptions
        case .islandLiveActivities: .islandOptions
        case .launcherFromIsland: .launcher
        case .systemMonitor: .systemTools
        case .fanControl: .systemTools
        case .monitorAlerts: .systemTools
        case .lowDiskWarning: .system
        case .systemNotices: .system
        case .volumeLevels: .system
        case .displayBrightness: .system
        case .quitProtection: .system
        case .batteryChargeLimit: .systemTools
        case .batterySailing: .systemTools
        case .batteryHeatProtection: .systemTools
        case .batteryCalibration: .systemTools
        case .keepAwake: .systemTools
        case .lidClosedAwake: .systemTools
        case .linkQuickFixes: .systemTools
        case .liveTimers: .activities
        case .dayCalendar: .activities
        case .dayWeather: .activities
        case .dayMarkets: .activities
        }
    }

    var title: String {
        switch self {
        case .t3Threads: String(localized: "T3 Threads")
        case .waitingAlerts: String(localized: "Waiting Alerts")
        case .fleetPanel: String(localized: "Fleet Panel")
        case .agentIsland: String(localized: "Agent Island")
        case .botHost: String(localized: "Bot Host")
        case .island: String(localized: "Island")
        case .islandExternalDisplays: String(localized: "External Displays")
        case .islandFullScreen: String(localized: "Full-Screen Apps")
        case .islandHoverOpen: String(localized: "Open on Hover")
        case .islandStatusMessages: String(localized: "Status Messages")
        case .islandLiveActivities: String(localized: "Live Activities")
        case .launcherFromIsland: String(localized: "Launcher from Island")
        case .systemMonitor: String(localized: "System Monitor")
        case .monitorAlerts: String(localized: "Monitor Alerts")
        case .fanControl: String(localized: "Fan Control")
        case .lowDiskWarning: String(localized: "Low Disk Warning")
        case .systemNotices: String(localized: "System Notices")
        case .volumeLevels: String(localized: "Volume in Island")
        case .displayBrightness: String(localized: "Display Brightness")
        case .quitProtection: String(localized: "Quit Protection")
        case .liveTimers: String(localized: "Timers")
        case .dayCalendar: String(localized: "Calendar")
        case .dayWeather: String(localized: "Weather")
        case .dayMarkets: String(localized: "Markets")
        case .batteryChargeLimit: String(localized: "Charge Limit")
        case .batterySailing: String(localized: "Battery Sailing")
        case .batteryHeatProtection: String(localized: "Battery Heat Protection")
        case .batteryCalibration: String(localized: "Battery Calibration")
        case .keepAwake: String(localized: "Keep Awake")
        case .lidClosedAwake: String(localized: "Keep Awake with Lid Closed")
        case .linkQuickFixes: String(localized: "Link Quick Fixes")
        }
    }

    var subtitle: String {
        switch self {
        case .t3Threads: String(localized: "Read T3 thread activity while requested.")
        case .waitingAlerts: String(localized: "Notify when an agent needs your answer or approval.")
        case .fleetPanel: String(localized: "Show T3 leads and workers across your Macs.")
        case .agentIsland: String(localized: "Show agent activity in the island.")
        case .botHost: String(localized: "Connect to local bots on demand.")
        case .island: String(localized: "Show the island at the top of the screen.")
        case .islandExternalDisplays: String(localized: "Show the island on external displays.")
        case .islandFullScreen: String(localized: "Show the island over full-screen apps.")
        case .islandHoverOpen: String(localized: "Open the island when the pointer hovers over it.")
        case .islandStatusMessages: String(localized: "Show status messages in the island.")
        case .islandLiveActivities: String(localized: "Show live activities in the island.")
        case .launcherFromIsland: String(localized: "Open the launcher from the island.")
        case .systemMonitor: String(localized: "Monitor system performance.")
        case .monitorAlerts: String(localized: "Evaluate alerts while the Monitor page is open.")
        case .fanControl: String(localized: "Control fans with the privileged helper.")
        case .lowDiskWarning: String(localized: "Warns below \(10)% or \(30) GB free.")
        case .systemNotices: String(localized: "Wi-Fi, Tailscale and low battery notices in the island.")
        case .volumeLevels: String(localized: "Replaces the macOS volume overlay.")
        case .displayBrightness: String(localized: "Brightness keys control every display, external ones too.")
        case .quitProtection: String(localized: "Stops an app from quitting on a single slip.")
        case .liveTimers: String(localized: "Countdowns and alarms in the island.")
        case .dayCalendar: String(localized: "Calendar events on the Day page.")
        case .dayWeather: String(localized: "Forecast from Open-Meteo on the Day page.")
        case .dayMarkets: String(localized: "Prices refresh every 3 minutes while Day is open.")
        case .batteryChargeLimit: String(localized: "Stop charging at the selected limit.")
        case .batterySailing: String(localized: "Use battery power above the charge limit.")
        case .batteryHeatProtection: String(localized: "Pause charging when the battery is hot.")
        case .batteryCalibration: String(localized: "Run a full battery calibration cycle.")
        case .keepAwake: String(localized: "Prevent idle sleep for the selected duration.")
        case .lidClosedAwake: String(localized: "Keep awake while the lid is closed.")
        case .linkQuickFixes: String(localized: "Offer manual fixes for connection problems.")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        switch self {
        case .volumeLevels: [.accessibility]
        case .displayBrightness: [.accessibility]
        case .quitProtection: [.accessibility]
        default: []
        }
    }
}

extension NotchcastFeature {
    var defaultEnabled: Bool {
        switch self {
        case .t3Threads: false
        case .waitingAlerts: false
        case .fleetPanel: false
        case .agentIsland: false
        case .botHost: false
        default: !isSystemFeature
        }
    }

    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        if isSystemFeature { return false }
        return switch self {
        case .t3Threads: false
        case .waitingAlerts: false
        case .fleetPanel: false
        case .agentIsland: false
        case .botHost: false
        case .displayBrightness: false
        case .quitProtection: false
        default: true
        }
    }

    var isSystemFeature: Bool { settingsGroup == .systemTools }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
}
