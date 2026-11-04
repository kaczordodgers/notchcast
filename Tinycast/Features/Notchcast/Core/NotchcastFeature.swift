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
    case pastePlain
    case finderCutPaste
    case finderRename
    case pasteImage
    case colorPicker
    case screenshot
    case dictationIslandHUD
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
    case buildStats

    var settingsGroup: SettingsGroup {
        switch self {
        case .buildStats: .buildStats
        case .island: .island
        case .islandExternalDisplays: .islandOptions
        case .islandFullScreen: .islandOptions
        case .islandHoverOpen: .islandOptions
        case .islandStatusMessages: .islandOptions
        case .islandLiveActivities: .islandOptions
        case .launcherFromIsland: .launcher
        case .colorPicker: .captureAndDictation
        case .screenshot: .captureAndDictation
        case .launcherNumberKeys: .launcher
        case .launcherAliasSpace: .launcher
        case .dictationIslandHUD: .activities
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
        case .pastePlain: .clipboard
        case .finderCutPaste: .finder
        case .finderRename: .finder
        case .pasteImage: .clipboard
        }
    }

    var title: String {
        switch self {
        case .buildStats: String(localized: "Build statistics")
        case .island: String(localized: "Island")
        case .islandExternalDisplays: String(localized: "External Displays")
        case .islandFullScreen: String(localized: "Full-Screen Apps")
        case .islandHoverOpen: String(localized: "Open on Hover")
        case .islandStatusMessages: String(localized: "Status Messages")
        case .islandLiveActivities: String(localized: "Live Activities")
        case .launcherFromIsland: String(localized: "Launcher from Island")
        case .launcherNumberKeys: String(localized: "Launcher Number Keys")
        case .launcherAliasSpace: String(localized: "Alias and Space")
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
        case .pastePlain: String(localized: "Paste Plain Text")
        case .finderCutPaste: String(localized: "Finder Cut and Paste")
        case .finderRename: String(localized: "Finder Rename")
        case .pasteImage: String(localized: "Paste Image in Finder")
        case .dayMarkets: String(localized: "Markets")
        case .colorPicker: String(localized: "Color Picker")
        case .screenshot: String(localized: "Screenshots")
        case .greenMaximize: String(localized: "Green Button Maximizes")
        case .middleClick: String(localized: "Trackpad Middle Click")
        case .hideCommandM: String(localized: "Hide with ⌘M")
        case .spacesOrder: String(localized: "Keep Spaces in a fixed order")
        case .showDesktop: String(localized: "Show Desktop with F3")
        case .dictationIslandHUD: String(localized: "Dictation in Island")
        case .batteryChargeLimit: String(localized: "Charge Limit")
        case .batterySailing: String(localized: "Battery Sailing")
        case .batteryHeatProtection: String(localized: "Battery Heat Protection")
        case .batteryCalibration: String(localized: "Battery Calibration")
        case .keepAwake: String(localized: "Keep Awake")
        case .lidClosedAwake: String(localized: "Keep Awake with Lid Closed")
        case .settingsBackup: String(localized: "Settings Backup")
        case .machineSetupProfile: String(localized: "Machine Setup Profile")
        case .agentConfirmation: String(localized: "Agent Confirmation")
        case .eventReminder: String(localized: "Event Reminders")
        case .switcherQuitKey: String(localized: "Switcher Quit Key")
        case .linkQuickFixes: String(localized: "Link Quick Fixes")
        }
    }

    var subtitle: String {
        switch self {
        case .buildStats: String(localized: "Read a local build snapshot.")
        case .island: String(localized: "Show the island at the top of the screen.")
        case .islandExternalDisplays: String(localized: "Show the island on external displays.")
        case .islandFullScreen: String(localized: "Show the island over full-screen apps.")
        case .islandHoverOpen: String(localized: "Open the island when the pointer hovers over it.")
        case .islandStatusMessages: String(localized: "Show status messages in the island.")
        case .islandLiveActivities: String(localized: "Show live activities in the island.")
        case .launcherFromIsland: String(localized: "Open the launcher from the island.")
        case .launcherNumberKeys: String(localized: "Open the first nine search results with Command-1 through Command-9.")
        case .launcherAliasSpace: String(localized: "Press Space after an exact alias to open its command.")
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
        case .pastePlain: String(localized: "Paste text without formatting from the launcher.")
        case .finderCutPaste: String(localized: "Use ⌘X and ⌘V to move files in Finder.")
        case .finderRename: String(localized: "Use Hyper+R to rename the selection in Finder.")
        case .pasteImage: String(localized: "Command+V saves clipboard images as PNG files in Finder.")
        case .dayMarkets: String(localized: "Prices refresh every 3 minutes while Day is open.")
        case .colorPicker: String(localized: "Copy a color from anywhere on the screen.")
        case .screenshot: String(localized: "Capture an area, window or display.")
        case .greenMaximize: String(localized: "Click the green button to maximize or restore; hold Option for macOS behavior.")
        case .middleClick: String(localized: "Three-finger taps and presses middle-click; paused during Three Finger Drag.")
        case .hideCommandM: String(localized: "Hide the front app instead of minimizing its window.")
        case .spacesOrder: String(localized: "Prevent automatic Spaces reordering and restore your setting when turned off.")
        case .showDesktop: String(localized: "Press F3 to show the desktop; press again to restore windows.")
        case .dictationIslandHUD: String(localized: "Show dictation status in the island.")
        case .batteryChargeLimit: String(localized: "Stop charging at the selected limit.")
        case .batterySailing: String(localized: "Use battery power above the charge limit.")
        case .batteryHeatProtection: String(localized: "Pause charging when the battery is hot.")
        case .batteryCalibration: String(localized: "Run a full battery calibration cycle.")
        case .keepAwake: String(localized: "Prevent idle sleep for the selected duration.")
        case .lidClosedAwake: String(localized: "Keep awake while the lid is closed.")
        case .settingsBackup: String(localized: "Back up safe Notchcast preferences daily.")
        case .machineSetupProfile: String(localized: "Plan portable setup imports and exports.")
        case .agentConfirmation: String(localized: "Ask before allowing agent requests.")
        case .eventReminder: String(localized: "Show calendar alerts in the island.")
        case .switcherQuitKey: String(localized: "Press Q in an empty window search to quit the selected app.")
        case .linkQuickFixes: String(localized: "Offer manual fixes for connection problems.")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        switch self {
        case .screenshot: [.screenRecording]
        case .showDesktop: [.accessibility]
        case .hideCommandM: [.accessibility]
        case .middleClick: [.accessibility]
        case .greenMaximize: [.accessibility]
        case .switcherQuitKey: [.accessibility]
        case .volumeLevels: [.accessibility]
        case .displayBrightness: [.accessibility]
        case .quitProtection: [.accessibility]
        case .pastePlain: [.accessibility]
        case .finderCutPaste: [.accessibility]
        case .finderRename: [.accessibility]
        case .pasteImage: [.accessibility]
        default: []
        }
    }
}

extension NotchcastFeature {
    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        if isSystemFeature { return false }
        return switch self {
        case .colorPicker: false
        case .screenshot: false
        case .buildStats: false
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
        case .pastePlain: false
        case .finderCutPaste: false
        case .finderRename: false
        case .pasteImage: false
        default: true
        }
    }

    var isLauncherKeysFeature: Bool { self == .launcherNumberKeys || self == .launcherAliasSpace }

    var defaultEnabled: Bool {
        switch self {
        case .pastePlain: false
        default: !isSystemFeature && self != .buildStats && self != .spacesOrder && self != .switcherQuitKey && !isLauncherKeysFeature
        }
    }

    var isSystemFeature: Bool { settingsGroup == .systemTools }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
    case screenRecording
}
