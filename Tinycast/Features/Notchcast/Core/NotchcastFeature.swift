import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case t3Threads
    case agentIsland
    case island, islandExternalDisplays, islandFullScreen, islandHoverOpen
    case islandStatusMessages, islandLiveActivities, launcherFromIsland
    case systemMonitor, fanControl
    case monitorAlerts
    case waitingAlerts
    case lowDiskWarning
    case systemNotices
    case volumeLevels
    case displayBrightness
    case quitProtection
    case liveTimers
    case dayWeather
    case dayMarkets
    case fleetPanel
    case batteryChargeLimit, batterySailing, batteryHeatProtection, batteryCalibration
    case keepAwake, lidClosedAwake

    enum SettingsGroup: Sendable {
        case island, islandOptions, launcher, system, activities
    }

    var settingsGroup: SettingsGroup {
        switch self {
        case .t3Threads: .activities
        case .agentIsland: .activities
        case .island: .island
        case .waitingAlerts: .activities
        case .islandExternalDisplays, .islandFullScreen, .islandHoverOpen,
             .islandStatusMessages, .islandLiveActivities: .islandOptions
        case .launcherFromIsland: .launcher
        case .fleetPanel: .activities
        case .systemMonitor, .fanControl, .monitorAlerts, .lowDiskWarning, .systemNotices,
             .volumeLevels, .displayBrightness, .quitProtection, .batteryChargeLimit,
             .batterySailing, .batteryHeatProtection, .batteryCalibration,
             .keepAwake, .lidClosedAwake: .system
        case .liveTimers, .dayWeather, .dayMarkets: .activities
        }
    }

    var title: String {
        switch self {
        case .t3Threads: String(localized: "T3 Threads")
        case .agentIsland: String(localized: "Agent Island")
        case .island: String(localized: "Island")
        case .waitingAlerts: String(localized: "Waiting Alerts")
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
        case .dayWeather: String(localized: "Weather")
        case .dayMarkets: String(localized: "Markets")
        case .fleetPanel: String(localized: "Fleet panel")
        case .batteryChargeLimit: String(localized: "Charge Limit")
        case .batterySailing: String(localized: "Battery Sailing")
        case .batteryHeatProtection: String(localized: "Battery Heat Protection")
        case .batteryCalibration: String(localized: "Battery Calibration")
        case .keepAwake: String(localized: "Keep Awake")
        case .lidClosedAwake: String(localized: "Keep Awake with Lid Closed")
        }
    }

    var subtitle: String {
        switch self {
        case .t3Threads: String(localized: "Read T3 thread activity while requested.")
        case .agentIsland: String(localized: "Show agent activity in the island.")
        case .island: String(localized: "Show the island at the top of the screen.")
        case .waitingAlerts: String(localized: "Notify when an agent needs your answer or approval.")
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
        case .dayWeather: String(localized: "Forecast from Open-Meteo on the Day page.")
        case .dayMarkets: String(localized: "Prices refresh every 3 minutes while Day is open.")
        case .fleetPanel: String(localized: "Show T3 leads and workers across your Macs.")
        case .batteryChargeLimit: String(localized: "Stop charging at the selected limit.")
        case .batterySailing: String(localized: "Use battery power above the charge limit.")
        case .batteryHeatProtection: String(localized: "Pause charging when the battery is hot.")
        case .batteryCalibration: String(localized: "Run a full battery calibration cycle.")
        case .keepAwake: String(localized: "Prevent idle sleep for the selected duration.")
        case .lidClosedAwake: String(localized: "Keep awake while the lid is closed.")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        switch self {
        case .t3Threads: []
        case .agentIsland: []
        case .volumeLevels, .displayBrightness, .quitProtection: [.accessibility]
        case .waitingAlerts: []
        case .fleetPanel: []
        case .island, .islandExternalDisplays, .islandFullScreen, .islandHoverOpen,
            .islandStatusMessages, .islandLiveActivities, .launcherFromIsland,
            .lowDiskWarning, .systemNotices, .liveTimers, .dayWeather, .dayMarkets,
            .systemMonitor, .monitorAlerts, .fanControl, .batteryChargeLimit, .batterySailing,
            .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake:
            []
        }
    }
}

extension NotchcastFeature {
    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        ![.t3Threads, .fleetPanel, .displayBrightness, .quitProtection].contains(self) && !isSystemFeature
    }

    var isSystemFeature: Bool {
        [.waitingAlerts, .systemMonitor, .monitorAlerts, .fanControl, .batteryChargeLimit, .batterySailing,
         .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake].contains(self)
    }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
}
