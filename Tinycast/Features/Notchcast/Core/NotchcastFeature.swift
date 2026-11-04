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
    case accessoryBatteries
    case monitorAlerts
    case lowDiskWarning
    case systemNotices
    case volumeLevels
    case audioPriority
    case displayBrightness
    case quitProtection
    case liveTimers
    case dayCalendar
    case dayWeather
    case dayMarkets
    case cleaningMode
    case appUpdates
    case macUpdate
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
    case cleanJunk
    case cleanHistory
    case cleanAIData
    case cleanDisk
    case cleanPurge
    case cleanOptimize
    case cleanSystem
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
    case startupItems
    case notificationCleanup
    case sudoTouchID
    case killProcess
    case macSetup
    case aiFeaturesOff
    case spotlightOff
    case privacyChoices
    case typingTweaks
    case finderTweaks
    case dockTweaks
    case appleAppsTweaks
    case iPhoneBackupTweaks
    case buildStats

    var settingsGroup: SettingsGroup {
        switch self {
        case .audioPriority: .systemTools
        case .cleaningMode: .tools
        case .appUpdates: .tools
        case .macUpdate: .tools
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
        case .accessoryBatteries: .systemTools
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
        case .cleanJunk: .clean
        case .cleanHistory: .clean
        case .cleanAIData: .clean
        case .cleanDisk: .clean
        case .cleanPurge: .clean
        case .cleanOptimize: .clean
        case .cleanSystem: .clean
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
        case .startupItems: .tweaks
        case .notificationCleanup: .tweaks
        case .sudoTouchID: .tweaks
        case .killProcess: .tweaks
        case .macSetup: .tweaks
        case .aiFeaturesOff: .tweaks
        case .spotlightOff: .tweaks
        case .privacyChoices: .tweaks
        case .typingTweaks: .tweaks
        case .finderTweaks: .tweaks
        case .dockTweaks: .tweaks
        case .appleAppsTweaks: .tweaks
        case .iPhoneBackupTweaks: .tweaks
        case .pastePlain: .clipboard
        case .finderCutPaste: .finder
        case .finderRename: .finder
        case .pasteImage: .clipboard
        }
    }

    var title: String {
        switch self {
        case .audioPriority: String(localized: "Audio device priority")
        case .cleaningMode: String(localized: "Cleaning mode")
        case .appUpdates: String(localized: "App updates")
        case .macUpdate: String(localized: "Update this Mac")
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
        case .accessoryBatteries: String(localized: "Accessory batteries")
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
        case .dictationIslandHUD: String(localized: "Dictation in Island")
        case .batteryChargeLimit: String(localized: "Charge Limit")
        case .batterySailing: String(localized: "Battery Sailing")
        case .batteryHeatProtection: String(localized: "Battery Heat Protection")
        case .batteryCalibration: String(localized: "Battery Calibration")
        case .keepAwake: String(localized: "Keep Awake")
        case .lidClosedAwake: String(localized: "Keep Awake with Lid Closed")
        case .cleanJunk: String(localized: "Junk")
        case .cleanHistory: String(localized: "Clean history")
        case .cleanAIData: String(localized: "AI data")
        case .cleanDisk: String(localized: "Disk analyzer")
        case .cleanPurge: String(localized: "Project purge")
        case .cleanOptimize: String(localized: "Optimize")
        case .cleanSystem: String(localized: "System root")
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
        case .audioPriority: String(localized: "Choose devices automatically when they connect or disconnect.")
        case .cleaningMode: String(localized: "Press Escape five times to exit; ends after 300 seconds.")
        case .appUpdates: String(localized: "Check installed apps for updates on demand.")
        case .macUpdate: String(localized: "Run maintenance only after confirmation.")
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
        case .monitorAlerts: String(localized: "Sample your Mac in the background while alerts are on.")
        case .fanControl: String(localized: "Control fans with the privileged helper.")
        case .accessoryBatteries: String(localized: "Show connected accessory battery levels.")
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
        case .startupItems: String(localized: "Manage user LaunchAgents and inspect system items.")
        case .notificationCleanup: String(localized: "Dismiss disk-ejection alerts automatically.")
        case .sudoTouchID: String(localized: "Use Touch ID to authorize sudo.")
        case .killProcess: String(localized: "Adds a command to stop a process.")
        case .macSetup: String(localized: "Apply reversible macOS preferences.")
        case .aiFeaturesOff: String(localized: "Choose which Apple intelligence features to disable.")
        case .spotlightOff: String(localized: "Turn off Spotlight indexing.")
        case .privacyChoices: String(localized: "Choose macOS privacy restrictions.")
        case .typingTweaks: String(localized: "Enable confirmed system preference changes.")
        case .finderTweaks: String(localized: "Enable confirmed system preference changes.")
        case .dockTweaks: String(localized: "Enable confirmed system preference changes.")
        case .appleAppsTweaks: String(localized: "Enable confirmed system preference changes.")
        case .iPhoneBackupTweaks: String(localized: "Enable confirmed system preference changes.")
        case .dictationIslandHUD: String(localized: "Show dictation status in the island.")
        case .batteryChargeLimit: String(localized: "Stop charging at the selected limit.")
        case .batterySailing: String(localized: "Use battery power above the charge limit.")
        case .batteryHeatProtection: String(localized: "Pause charging when the battery is hot.")
        case .batteryCalibration: String(localized: "Run a full battery calibration cycle.")
        case .keepAwake: String(localized: "Prevent idle sleep for the selected duration.")
        case .lidClosedAwake: String(localized: "Keep awake while the lid is closed.")
        case .cleanJunk: String(localized: "Runs only when you click an action.")
        case .cleanHistory: String(localized: "Runs only when you click an action.")
        case .cleanAIData: String(localized: "Runs only when you click an action.")
        case .cleanDisk: String(localized: "Runs only when you click an action.")
        case .cleanPurge: String(localized: "Runs only when you click an action.")
        case .cleanOptimize: String(localized: "Runs only when you click an action.")
        case .cleanSystem: String(localized: "Runs only when you click an action.")
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
        case .cleaningMode: [.accessibility]
        case .screenshot: [.screenRecording]
        case .showDesktop: [.accessibility]
        case .hideCommandM: [.accessibility]
        case .middleClick: [.accessibility]
        case .greenMaximize: [.accessibility]
        case .switcherQuitKey: [.accessibility]
        case .volumeLevels: [.accessibility]
        case .displayBrightness: [.accessibility]
        case .quitProtection: [.accessibility]
        case .notificationCleanup: [.accessibility]
        case .startupItems: []
        case .sudoTouchID: []
        case .killProcess: []
        case .macSetup: []
        case .aiFeaturesOff: []
        case .spotlightOff: []
        case .privacyChoices: []
        case .island: []
        case .islandExternalDisplays: []
        case .islandFullScreen: []
        case .islandHoverOpen: []
        case .islandStatusMessages: []
        case .islandLiveActivities: []
        case .launcherFromIsland: []
        case .lowDiskWarning: []
        case .systemNotices: []
        case .liveTimers: []
        case .dayWeather: []
        case .dayMarkets: []
        case .typingTweaks: []
        case .finderTweaks: []
        case .dockTweaks: []
        case .appleAppsTweaks: []
        case .iPhoneBackupTweaks: []
        case .systemMonitor: []
        case .monitorAlerts: []
        case .fanControl: []
        case .batteryChargeLimit: []
        case .batterySailing: []
        case .batteryHeatProtection: []
        case .batteryCalibration: []
        case .keepAwake: []
        case .lidClosedAwake: []
        case .pastePlain: [.accessibility]
        case .finderCutPaste: [.accessibility]
        case .finderRename: [.accessibility]
        case .pasteImage: [.accessibility]
        default: []
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
        if isSystemFeature || isSystemTweak || settingsGroup == .clean { return false }
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

    var isSystemTweak: Bool {
        switch self {
        case .startupItems: true
        case .notificationCleanup: true
        case .sudoTouchID: true
        case .killProcess: true
        case .macSetup: true
        case .aiFeaturesOff: true
        case .spotlightOff: true
        case .privacyChoices: true
        case .typingTweaks: true
        case .finderTweaks: true
        case .dockTweaks: true
        case .appleAppsTweaks: true
        case .iPhoneBackupTweaks: true
        default: false
        }
    }
    var isLauncherKeysFeature: Bool { self == .launcherNumberKeys || self == .launcherAliasSpace }

    var defaultEnabled: Bool {
        !isSystemFeature && !isSystemTweak && settingsGroup != .clean && self != .buildStats && self != .spacesOrder && self != .switcherQuitKey && self != .pastePlain && !isLauncherKeysFeature
    }

    var isSystemFeature: Bool { settingsGroup == .systemTools || settingsGroup == .tools }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
    case screenRecording
}
