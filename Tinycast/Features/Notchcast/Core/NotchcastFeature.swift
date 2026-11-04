import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case island
    case islandExternalDisplays
    case islandFullScreen
    case islandHoverOpen
    case islandStatusMessages
    case islandLiveActivities
    case launcherFromIsland
    case launcherNumberKeys
    case launcherAliasSpace
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
    case settingsBackup
    case showDesktop
    case spacesOrder
    case hideCommandM
    case middleClick
    case greenMaximize
    case machineSetupProfile
    case agentConfirmation
    case eventReminder
    case switcherQuitKey
    case linkQuickFixes

    var settingsGroup: SettingsGroup {
        switch self {
        case .island: .island
        case .islandExternalDisplays: .islandOptions
        case .islandFullScreen: .islandOptions
        case .islandHoverOpen: .islandOptions
        case .islandStatusMessages: .islandOptions
        case .islandLiveActivities: .islandOptions
        case .launcherFromIsland: .launcher
        case .launcherNumberKeys: .launcher
        case .launcherAliasSpace: .launcher
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
        case .settingsBackup: .system
        case .showDesktop: .system
        case .spacesOrder: .system
        case .hideCommandM: .system
        case .middleClick: .system
        case .greenMaximize: .system
        case .machineSetupProfile: .system
        case .agentConfirmation: .islandOptions
        case .eventReminder: .activities
        case .switcherQuitKey: .launcher
        }
    }

    var title: String {
        switch self {
        case .island: String(localized: "Island", table: "Notchcast")
        case .islandExternalDisplays: String(localized: "External Displays", table: "Notchcast")
        case .islandFullScreen: String(localized: "Full-Screen Apps", table: "Notchcast")
        case .islandHoverOpen: String(localized: "Open on Hover", table: "Notchcast")
        case .islandStatusMessages: String(localized: "Status Messages", table: "Notchcast")
        case .islandLiveActivities: String(localized: "Live Activities", table: "Notchcast")
        case .launcherFromIsland: String(localized: "Launcher from Island", table: "Notchcast")
        case .launcherNumberKeys: String(localized: "Launcher Number Keys", table: "Notchcast")
        case .launcherAliasSpace: String(localized: "Alias and Space", table: "Notchcast")
        case .systemMonitor: String(localized: "System Monitor", table: "Notchcast")
        case .monitorAlerts: String(localized: "Monitor Alerts", table: "Notchcast")
        case .fanControl: String(localized: "Fan Control", table: "Notchcast")
        case .lowDiskWarning: String(localized: "Low Disk Warning", table: "Notchcast")
        case .systemNotices: String(localized: "System Notices", table: "Notchcast")
        case .volumeLevels: String(localized: "Volume in Island", table: "Notchcast")
        case .displayBrightness: String(localized: "Display Brightness", table: "Notchcast")
        case .quitProtection: String(localized: "Quit Protection", table: "Notchcast")
        case .liveTimers: String(localized: "Timers", table: "Notchcast")
        case .dayCalendar: String(localized: "Calendar")
        case .dayWeather: String(localized: "Weather")
        case .dayMarkets: String(localized: "Markets", table: "Notchcast")
        case .greenMaximize: String(localized: "Green Button Maximizes", table: "Notchcast")
        case .middleClick: String(localized: "Trackpad Middle Click", table: "Notchcast")
        case .hideCommandM: String(localized: "Hide with ⌘M", table: "Notchcast")
        case .spacesOrder: String(localized: "Keep Spaces in a fixed order", table: "Notchcast")
        case .showDesktop: String(localized: "Show Desktop with F3", table: "Notchcast")
        case .batteryChargeLimit: String(localized: "Charge Limit", table: "Notchcast")
        case .batterySailing: String(localized: "Battery Sailing", table: "Notchcast")
        case .batteryHeatProtection: String(localized: "Battery Heat Protection", table: "Notchcast")
        case .batteryCalibration: String(localized: "Battery Calibration", table: "Notchcast")
        case .keepAwake: String(localized: "Keep Awake", table: "Notchcast")
        case .lidClosedAwake: String(localized: "Keep Awake with Lid Closed", table: "Notchcast")
        case .settingsBackup: String(localized: "Settings Backup", table: "Notchcast")
        case .machineSetupProfile: String(localized: "Machine Setup Profile", table: "Notchcast")
        case .agentConfirmation: String(localized: "Agent Confirmation", table: "Notchcast")
        case .eventReminder: String(localized: "Event Reminders", table: "Notchcast")
        case .switcherQuitKey: String(localized: "Switcher Quit Key", table: "Notchcast")
        case .linkQuickFixes: String(localized: "Link Quick Fixes", table: "Notchcast")
        }
    }

    var subtitle: String {
        switch self {
        case .island: String(localized: "Show the island at the top of the screen.", table: "Notchcast")
        case .islandExternalDisplays: String(localized: "Show the island on external displays.", table: "Notchcast")
        case .islandFullScreen: String(localized: "Show the island over full-screen apps.", table: "Notchcast")
        case .islandHoverOpen: String(localized: "Open the island when the pointer hovers over it.", table: "Notchcast")
        case .islandStatusMessages: String(localized: "Show status messages in the island.", table: "Notchcast")
        case .islandLiveActivities: String(localized: "Show live activities in the island.", table: "Notchcast")
        case .launcherFromIsland: String(localized: "Open the launcher from the island.", table: "Notchcast")
        case .launcherNumberKeys: String(localized: "Open the first nine search results with Command-1 through Command-9.", table: "Notchcast")
        case .launcherAliasSpace: String(localized: "Press Space after an exact alias to open its command.", table: "Notchcast")
        case .systemMonitor: String(localized: "Monitor system performance.", table: "Notchcast")
        case .monitorAlerts: String(localized: "Evaluate alerts while the Monitor page is open.", table: "Notchcast")
        case .fanControl: String(localized: "Control fans with the privileged helper.", table: "Notchcast")
        case .lowDiskWarning: String(localized: "Warns below \(10)% or \(30) GB free.", table: "Notchcast")
        case .systemNotices: String(localized: "Wi-Fi, Tailscale and low battery notices in the island.", table: "Notchcast")
        case .volumeLevels: String(localized: "Replaces the macOS volume overlay.", table: "Notchcast")
        case .displayBrightness: String(localized: "Brightness keys control every display, external ones too.", table: "Notchcast")
        case .quitProtection: String(localized: "Stops an app from quitting on a single slip.", table: "Notchcast")
        case .liveTimers: String(localized: "Countdowns and alarms in the island.", table: "Notchcast")
        case .dayCalendar: String(localized: "Calendar events on the Day page.", table: "Notchcast")
        case .dayWeather: String(localized: "Forecast from Open-Meteo on the Day page.", table: "Notchcast")
        case .dayMarkets: String(localized: "Prices refresh every 3 minutes while Day is open.", table: "Notchcast")
        case .greenMaximize: String(localized: "Click the green button to maximize or restore; hold Option for macOS behavior.", table: "Notchcast")
        case .middleClick: String(localized: "Three-finger taps and presses middle-click; paused during Three Finger Drag.", table: "Notchcast")
        case .hideCommandM: String(localized: "Hide the front app instead of minimizing its window.", table: "Notchcast")
        case .spacesOrder: String(localized: "Prevent automatic Spaces reordering and restore your setting when turned off.", table: "Notchcast")
        case .showDesktop: String(localized: "Press F3 to show the desktop; press again to restore windows.", table: "Notchcast")
        case .batteryChargeLimit: String(localized: "Stop charging at the selected limit.", table: "Notchcast")
        case .batterySailing: String(localized: "Use battery power above the charge limit.", table: "Notchcast")
        case .batteryHeatProtection: String(localized: "Pause charging when the battery is hot.", table: "Notchcast")
        case .batteryCalibration: String(localized: "Run a full battery calibration cycle.", table: "Notchcast")
        case .keepAwake: String(localized: "Prevent idle sleep for the selected duration.", table: "Notchcast")
        case .lidClosedAwake: String(localized: "Keep awake while the lid is closed.", table: "Notchcast")
        case .settingsBackup: String(localized: "Back up safe Notchcast preferences daily.", table: "Notchcast")
        case .machineSetupProfile: String(localized: "Plan portable setup imports and exports.", table: "Notchcast")
        case .agentConfirmation: String(localized: "Ask before allowing agent requests.", table: "Notchcast")
        case .eventReminder: String(localized: "Show calendar alerts in the island.", table: "Notchcast")
        case .switcherQuitKey: String(localized: "Press Q in an empty window search to quit the selected app.", table: "Notchcast")
        case .linkQuickFixes: String(localized: "Offer manual fixes for connection problems.", table: "Notchcast")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        switch self {
        case .showDesktop: [.accessibility]
        case .hideCommandM: [.accessibility]
        case .middleClick: [.accessibility]
        case .greenMaximize: [.accessibility]
        case .switcherQuitKey: [.accessibility]
        case .volumeLevels: [.accessibility]
        case .displayBrightness: [.accessibility]
        case .quitProtection: [.accessibility]
        default: []
        }
    }
}

extension NotchcastFeature {
    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        if isSystemFeature { return false }
        return switch self {
        case .launcherNumberKeys: false
        case .launcherAliasSpace: false
        case .settingsBackup: false
        case .showDesktop: false
        case .spacesOrder: false
        case .hideCommandM: false
        case .middleClick: false
        case .greenMaximize: false
        case .machineSetupProfile: false
        case .switcherQuitKey: false
        case .displayBrightness: false
        case .quitProtection: false
        default: true
        }
    }

    var isLauncherKeysFeature: Bool { self == .launcherNumberKeys || self == .launcherAliasSpace }

    var defaultEnabled: Bool {
        !isSystemFeature && self != .spacesOrder && self != .switcherQuitKey && !isLauncherKeysFeature
    }

    var isSystemFeature: Bool { settingsGroup == .systemTools }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
}
