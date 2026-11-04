import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
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
    case aiUsage
    case aiUsageOtherMac
    case machLink
    case machRemote
    case backupStatus
    case linkHealth
    case shelfBetweenMacs
    case sendFiles
    case updateRemote
    case batteryChargeLimit
    case batterySailing
    case batteryHeatProtection
    case batteryCalibration
    case keepAwake
    case lidClosedAwake

    var settingsGroup: SettingsGroup {
        switch self {
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
        case .liveTimers: .activities
        case .dayCalendar: .activities
        case .dayWeather: .activities
        case .dayMarkets: .activities
        case .aiUsage: .activities
        case .aiUsageOtherMac: .activities
        case .machLink: .system
        case .machRemote: .system
        case .backupStatus: .system
        case .linkHealth: .system
        case .shelfBetweenMacs: .activities
        case .sendFiles: .system
        case .updateRemote: .system
        }
    }

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
        case .dayCalendar: String(localized: "Calendar")
        case .dayWeather: String(localized: "Weather")
        case .dayMarkets: String(localized: "Markets")
        case .aiUsage: String(localized: "AI Usage")
        case .aiUsageOtherMac: String(localized: "Other Mac AI Usage")
        case .machLink: String(localized: "Mac Link")
        case .machRemote: String(localized: "Remote Mac")
        case .backupStatus: String(localized: "Backup Status")
        case .linkHealth: String(localized: "Link Health")
        case .shelfBetweenMacs: String(localized: "Shelf between Macs")
        case .sendFiles: String(localized: "Send to Remote Mac")
        case .updateRemote: String(localized: "Update Remote Mac")
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
        case .dayCalendar: String(localized: "Calendar events on the Day page.")
        case .dayWeather: String(localized: "Forecast from Open-Meteo on the Day page.")
        case .dayMarkets: String(localized: "Prices refresh every 3 minutes while Day is open.")
        case .aiUsage: String(localized: "Read local AI usage on demand.")
        case .aiUsageOtherMac: String(localized: "Include usage from the other Mac.")
        case .machLink: String(localized: "Connect to a paired Mac on the local network.")
        case .machRemote: String(localized: "Connect to the remote Mac using SSH.")
        case .backupStatus: String(localized: "Warns when backups fail or become stale.")
        case .linkHealth: String(localized: "Notify when the paired Mac disconnects or reconnects.")
        case .shelfBetweenMacs: String(localized: "Send small items to the paired Mac.")
        case .sendFiles: String(localized: "Send selected files to the remote Mac.")
        case .updateRemote: String(localized: "Run the update on the remote Mac.")
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
        if startsOff { return false }
        return switch self {
        case .displayBrightness: false
        case .quitProtection: false
        default: true
        }
    }

    var startsOff: Bool {
        if isSystemFeature { return true }
        return switch self {
        case .aiUsage: true
        case .aiUsageOtherMac: true
        case .machLink: true
        case .machRemote: true
        case .backupStatus: true
        case .linkHealth: true
        case .shelfBetweenMacs: true
        case .sendFiles: true
        case .updateRemote: true
        default: false
        }
    }

    var isSystemFeature: Bool { settingsGroup == .systemTools }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
}
