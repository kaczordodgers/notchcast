import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case urlCleaner
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
    case dayCalendar
    case dayWeather
    case dayMarkets
    case convertFiles
    case batteryChargeLimit, batterySailing, batteryHeatProtection, batteryCalibration
    case keepAwake, lidClosedAwake
    case mediaTools

    case commandRunner
    case downloads, downloadsAria2, distill, distillTimestamps, distillConvert

    enum SettingsGroup: Sendable {
        case island, islandOptions, launcher, system, activities
    }

    var settingsGroup: SettingsGroup {
        switch self {
        case .mediaTools: .activities
        case .commandRunner: .launcher
        case .urlCleaner: .system
        case .island: .island
        case .islandExternalDisplays, .islandFullScreen, .islandHoverOpen,
             .islandStatusMessages, .islandLiveActivities: .islandOptions
        case .launcherFromIsland: .launcher
        case .systemMonitor, .fanControl, .monitorAlerts, .lowDiskWarning, .systemNotices,
             .volumeLevels, .displayBrightness, .quitProtection, .batteryChargeLimit,
             .batterySailing, .batteryHeatProtection, .batteryCalibration,
             .keepAwake, .lidClosedAwake: .system
                case .convertFiles: .activities
        case .liveTimers, .dayCalendar, .dayWeather, .dayMarkets, .downloads, .downloadsAria2, .distill,
             .distillTimestamps, .distillConvert: .activities
        }
    }

    var title: String {
        switch self {
        case .mediaTools: String(localized: "Media Tools")
        case .commandRunner: String(localized: "Command Runner")
        case .urlCleaner: String(localized: "URL cleaner")
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
        case .convertFiles: String(localized: "Convert Files")
        case .batteryChargeLimit: String(localized: "Charge Limit")
        case .batterySailing: String(localized: "Battery Sailing")
        case .batteryHeatProtection: String(localized: "Battery Heat Protection")
        case .batteryCalibration: String(localized: "Battery Calibration")
        case .keepAwake: String(localized: "Keep Awake")
        case .lidClosedAwake: String(localized: "Keep Awake with Lid Closed")
        case .downloads: String(localized: "Downloads")
        case .downloadsAria2: String(localized: "Fast Downloads with aria2c")
        case .distill: String(localized: "Distill")
        case .distillTimestamps: String(localized: "Distill Timestamps")
        case .distillConvert: String(localized: "Convert Distill Folder")
        }
    }

    var subtitle: String {
        switch self {
        case .mediaTools: String(localized: "Compress media, make GIFs and extract text locally.")
        case .commandRunner: String(localized: "Run commands from a host profile.")
        case .urlCleaner: String(localized: "Remove tracking parameters from copied links.")
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
        case .convertFiles: String(localized: "Convert local files beside the originals.")
        case .batteryChargeLimit: String(localized: "Stop charging at the selected limit.")
        case .batterySailing: String(localized: "Use battery power above the charge limit.")
        case .batteryHeatProtection: String(localized: "Pause charging when the battery is hot.")
        case .batteryCalibration: String(localized: "Run a full battery calibration cycle.")
        case .keepAwake: String(localized: "Prevent idle sleep for the selected duration.")
        case .lidClosedAwake: String(localized: "Keep awake while the lid is closed.")
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
        case .mediaTools: []
        case .commandRunner: []
        case .urlCleaner: []
        case .downloads, .downloadsAria2, .distill, .distillTimestamps, .distillConvert: []
        case .volumeLevels, .displayBrightness, .quitProtection: [.accessibility]
        case .convertFiles: []
        case .island, .islandExternalDisplays, .islandFullScreen, .islandHoverOpen,
            .islandStatusMessages, .islandLiveActivities, .launcherFromIsland,
            .lowDiskWarning, .systemNotices, .liveTimers, .dayCalendar, .dayWeather, .dayMarkets,
            .systemMonitor, .monitorAlerts, .fanControl, .batteryChargeLimit, .batterySailing,
            .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake:
            []
        }
    }
}

extension NotchcastFeature {
    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        ![.urlCleaner, .convertFiles, .mediaTools, .commandRunner, .displayBrightness, .quitProtection].contains(self)
            && !isSystemFeature && !isDownloadsFeature
    }

    var defaultEnabled: Bool {
        ![.urlCleaner, .convertFiles, .mediaTools, .commandRunner].contains(self) && !isSystemFeature
    }

    var isSystemFeature: Bool {
        [.systemMonitor, .monitorAlerts, .fanControl, .batteryChargeLimit, .batterySailing,
         .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake].contains(self)
    }

    var isDownloadsFeature: Bool {
        [.downloads, .downloadsAria2, .distill, .distillTimestamps, .distillConvert].contains(self)
    }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
}
