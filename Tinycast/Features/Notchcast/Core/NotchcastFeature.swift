import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case island, islandExternalDisplays, islandFullScreen, islandHoverOpen
    case islandStatusMessages, islandLiveActivities, launcherFromIsland
    case systemMonitor, fanControl
    case monitorAlerts
    case lowDiskWarning
    case systemNotices
    case volumeLevels
    case displayBrightness
    case quitProtection
    case liveTimers
    case dayWeather
    case dayMarkets
    case startupItems, notificationCleanup, sudoTouchID, killProcess
    case macSetup, aiFeaturesOff, spotlightOff, privacyChoices
    case typingTweaks, finderTweaks, dockTweaks, appleAppsTweaks, iPhoneBackupTweaks
    case batteryChargeLimit, batterySailing, batteryHeatProtection, batteryCalibration
    case keepAwake, lidClosedAwake

    var title: String {
        switch self {
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
        case .dayWeather: String(localized: "Weather")
        case .dayMarkets: String(localized: "Markets")
        case .startupItems: String(localized: "Startup Items")
        case .notificationCleanup: String(localized: "Notification Cleanup")
        case .sudoTouchID: String(localized: "Touch ID for sudo")
        case .killProcess: String(localized: "Kill Process")
        case .macSetup: String(localized: "Mac Setup Presets")
        case .aiFeaturesOff: String(localized: "AI Features Off")
        case .spotlightOff: String(localized: "Spotlight Indexing Off")
        case .privacyChoices: String(localized: "Privacy Choices")
        case .typingTweaks: String(localized: "Typing")
        case .finderTweaks: String(localized: "Finder")
        case .dockTweaks: String(localized: "Dock and windows")
        case .appleAppsTweaks: String(localized: "Apple apps")
        case .iPhoneBackupTweaks: String(localized: "iPhone backup")
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
        case .dayWeather: String(localized: "Forecast from Open-Meteo on the Day page.")
        case .dayMarkets: String(localized: "Prices refresh every 3 minutes while Day is open.")
        case .startupItems: String(localized: "Manage user LaunchAgents and inspect system items.")
        case .notificationCleanup: String(localized: "Dismiss disk-ejection alerts automatically.")
        case .sudoTouchID: String(localized: "Use Touch ID to authorize sudo.")
        case .killProcess: String(localized: "Adds a command to stop a process.")
        case .macSetup: String(localized: "Apply reversible macOS preferences.")
        case .aiFeaturesOff: String(localized: "Choose which Apple intelligence features to disable.")
        case .spotlightOff: String(localized: "Turn off Spotlight indexing.")
        case .privacyChoices: String(localized: "Choose macOS privacy restrictions.")
        case .typingTweaks, .finderTweaks, .dockTweaks, .appleAppsTweaks, .iPhoneBackupTweaks:
            String(localized: "Enable confirmed system preference changes.")
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
        case .volumeLevels, .displayBrightness, .quitProtection, .notificationCleanup: [.accessibility]
        case .startupItems, .sudoTouchID, .killProcess, .macSetup, .aiFeaturesOff,
            .spotlightOff, .privacyChoices: []
        case .island, .islandExternalDisplays, .islandFullScreen, .islandHoverOpen,
            .islandStatusMessages, .islandLiveActivities, .launcherFromIsland,
            .lowDiskWarning, .systemNotices, .liveTimers, .dayWeather, .dayMarkets,
            .typingTweaks, .finderTweaks, .dockTweaks, .appleAppsTweaks, .iPhoneBackupTweaks,
            .systemMonitor, .monitorAlerts, .fanControl, .batteryChargeLimit, .batterySailing,
            .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake:
            []
        }
    }
}

extension NotchcastFeature {
    var isWired: Bool {
        ![Self.killProcess, .macSetup, .aiFeaturesOff, .privacyChoices].contains(self)
    }

    static var systemToolsSettingsFeatures: [Self] {
        [.startupItems, .notificationCleanup, .sudoTouchID, .killProcess,
         .macSetup, .aiFeaturesOff, .spotlightOff, .privacyChoices].filter(\.isWired)
    }

    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        self != .displayBrightness && self != .quitProtection && !isSystemFeature && !isSystemTweak
    }

    var isSystemTweak: Bool {
        switch self {
        case .startupItems, .notificationCleanup, .sudoTouchID, .killProcess,
            .macSetup, .aiFeaturesOff, .spotlightOff, .privacyChoices,
            .typingTweaks, .finderTweaks, .dockTweaks, .appleAppsTweaks, .iPhoneBackupTweaks: true
        default: false
        }
    }

    var defaultEnabled: Bool { !isSystemFeature && !isSystemTweak }

    var isSystemFeature: Bool {
        [.systemMonitor, .monitorAlerts, .fanControl, .batteryChargeLimit, .batterySailing,
         .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake].contains(self)
    }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
}
