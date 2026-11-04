import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case githubSearch
    case clearNotifications
    case launcherAnswers
    case copyPath
    case smallCommands
    case aiUsage
    case aiUsageOtherMac
    case machLink
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
    case downloads
    case downloadsAria2
    case distill
    case distillTimestamps
    case distillConvert

    case urlCleaner

    case convertFiles

    case mediaTools

    case commandRunner
    case buildStats

    var settingsGroup: SettingsGroup {
        switch self {
        case .githubSearch: .launcher
        case .clearNotifications: .launcher
        case .launcherAnswers: .launcher
        case .copyPath: .launcher
        case .smallCommands: .launcher
        case .aiUsage: .activities
        case .aiUsageOtherMac: .activities
        case .machLink: .system
        case .commandRunner: .launcher
        case .mediaTools: .activities
        case .convertFiles: .activities
        case .urlCleaner: .system
        case .buildStats: .buildStats
        case .island: .island
        case .islandExternalDisplays: .islandOptions
        case .islandFullScreen: .islandOptions
        case .islandHoverOpen: .islandOptions
        case .islandStatusMessages: .islandOptions
        case .islandLiveActivities: .islandOptions
        case .launcherFromIsland: .launcher
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
        case .downloads: .activities
        case .downloadsAria2: .activities
        case .distill: .activities
        case .distillTimestamps: .activities
        case .distillConvert: .activities
        }
    }

    var title: String {
        switch self {
        case .githubSearch: String(localized: "GitHub Search")
        case .clearNotifications: String(localized: "Clear Notifications")
        case .launcherAnswers: String(localized: "Currency Answers")
        case .copyPath: String(localized: "Copy Path")
        case .smallCommands: String(localized: "Small Commands")
        case .aiUsage: String(localized: "AI Usage")
        case .aiUsageOtherMac: String(localized: "Other Mac AI Usage")
        case .machLink: String(localized: "Mac Link")
        case .commandRunner: String(localized: "Command Runner")
        case .mediaTools: String(localized: "Media Tools")
        case .convertFiles: String(localized: "Convert Files")
        case .urlCleaner: String(localized: "URL cleaner")
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
        case .dayMarkets: String(localized: "Markets")
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
        case .downloads: String(localized: "Downloads")
        case .downloadsAria2: String(localized: "Fast Downloads with aria2c")
        case .distill: String(localized: "Distill")
        case .distillTimestamps: String(localized: "Distill Timestamps")
        case .distillConvert: String(localized: "Convert Distill Folder")
        }
    }

    var subtitle: String {
        switch self {
        case .githubSearch: String(localized: "Search GitHub repositories and starred projects.")
        case .clearNotifications: String(localized: "Clear notifications from Notification Center. Requires English system language.")
        case .launcherAnswers: String(localized: "Currency answers using rates from NBP.")
        case .copyPath: String(localized: "Copy the frontmost document path or browser link.")
        case .smallCommands: String(localized: "Passwords, short links, noise control and AirDrop. Noise control requires English system language.")
        case .aiUsage: String(localized: "Read local AI usage on demand.")
        case .aiUsageOtherMac: String(localized: "Include usage from the other Mac.")
        case .machLink: String(localized: "Connect to a paired Mac on the local network.")
        case .commandRunner: String(localized: "Run commands from a host profile.")
        case .mediaTools: String(localized: "Compress media, make GIFs and extract text locally.")
        case .convertFiles: String(localized: "Convert local files beside the originals.")
        case .urlCleaner: String(localized: "Remove tracking parameters from copied links.")
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
        case .dayMarkets: String(localized: "Prices refresh every 3 minutes while Day is open.")
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
        case .downloads: String(localized: "Download video, audio, transcripts and webpages from clipboard links.")
        case .downloadsAria2: String(localized: "Use aria2c for faster media downloads when it is installed.")
        case .distill: String(localized: "Save links and transcribe media into your Distill folder.")
        case .distillTimestamps: String(localized: "Include approximate chunk timestamps in Distill transcripts.")
        case .distillConvert: String(localized: "Convert files in your Distill folder to Markdown or text.")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        switch self {
        case .clearNotifications: [.accessibility]
        case .copyPath: [.accessibility]
        case .smallCommands: [.accessibility]
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
        case .githubSearch: false
        case .clearNotifications: false
        case .launcherAnswers: false
        case .copyPath: false
        case .smallCommands: false
        case .aiUsage: false
        case .aiUsageOtherMac: false
        case .machLink: false
        case .buildStats: false
        case .launcherNumberKeys: false
        case .launcherAliasSpace: false
        case .urlCleaner: false
        case .convertFiles: false
        case .mediaTools: false
        case .commandRunner: false
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
        case .downloads: false
        case .downloadsAria2: false
        case .distill: false
        case .distillTimestamps: false
        case .distillConvert: false
        default: true
        }
    }

    var isLauncherKeysFeature: Bool { self == .launcherNumberKeys || self == .launcherAliasSpace }

    var defaultEnabled: Bool {
        switch self {
        case .githubSearch: false
        case .clearNotifications: false
        case .launcherAnswers: false
        case .copyPath: false
        case .smallCommands: false
        case .aiUsage: false
        case .aiUsageOtherMac: false
        case .machLink: false
        case .spacesOrder: false
        case .switcherQuitKey: false
        case .urlCleaner: false
        case .convertFiles: false
        case .mediaTools: false
        case .commandRunner: false
        case .buildStats: false
        default: !isSystemFeature && !isLauncherKeysFeature
        }
    }

    var isSystemFeature: Bool { settingsGroup == .systemTools }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
}
