import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case island
    case islandExternalDisplays
    case islandFullScreen
    case islandHoverOpen
    case islandStatusMessages
    case islandLiveActivities
    case launcherFromIsland
    case musicNowPlaying
    case musicLastPlayer
    case musicBlockAppleMusic
    case spotifyConnect
    case microphoneMute
    case inUseMarks
    case systemMonitor
    case fanControl
    case monitorAlerts
    case lowDiskWarning
    case systemNotices
    case volumeLevels
    case displayBrightness
    case quitProtection
    case liveTimers
    case dayWeather
    case dayMarkets
    case batteryChargeLimit
    case batterySailing
    case batteryHeatProtection
    case batteryCalibration
    case keepAwake
    case lidClosedAwake
    case archives
    case archivesInPlace
    case archivesDefaultApp
    case torrents
    case torrentsUseIPhone
    case torrentsKeepSharing

    var defaultOn: Bool {
        switch self {
        case .island: true
        case .islandExternalDisplays: true
        case .islandFullScreen: true
        case .islandHoverOpen: true
        case .islandStatusMessages: true
        case .islandLiveActivities: true
        case .launcherFromIsland: true
        case .musicNowPlaying: true
        case .musicLastPlayer: true
        case .musicBlockAppleMusic: true
        case .spotifyConnect: false
        case .microphoneMute: true
        case .inUseMarks: true
        case .systemMonitor: false
        case .fanControl: false
        case .monitorAlerts: false
        case .lowDiskWarning: true
        case .systemNotices: true
        case .volumeLevels: true
        case .displayBrightness: true
        case .quitProtection: true
        case .liveTimers: true
        case .dayWeather: true
        case .dayMarkets: true
        case .batteryChargeLimit: false
        case .batterySailing: false
        case .batteryHeatProtection: false
        case .batteryCalibration: false
        case .keepAwake: false
        case .archives: true
        case .archivesInPlace: false
        case .archivesDefaultApp: false
        case .torrents: true
        case .torrentsUseIPhone: true
        case .torrentsKeepSharing: false
        case .lidClosedAwake: false
        }
    }

    var dependencies: [Self] {
        switch self {
        case .archives: []
        case .archivesInPlace: [.archives]
        case .archivesDefaultApp: [.archives]
        case .torrents: []
        case .torrentsUseIPhone: [.torrents]
        case .torrentsKeepSharing: [.torrents]
        case .island: []
        case .musicLastPlayer: [.island, .musicNowPlaying]
        case .spotifyConnect: [.island, .musicNowPlaying]
        default: needsIsland ? [.island] : []
        }
    }

    var settingsGroup: SettingsGroup {
        switch self {
        case .musicNowPlaying: .music
        case .musicLastPlayer: .music
        case .musicBlockAppleMusic: .music
        case .spotifyConnect: .music
        case .microphoneMute: .music
        case .inUseMarks: .music
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
        case .dayWeather: .activities
        case .dayMarkets: .activities
        case .archives: .archives
        case .archivesInPlace: .archives
        case .archivesDefaultApp: .archives
        case .torrents: .torrents
        case .torrentsUseIPhone: .torrents
        case .torrentsKeepSharing: .torrents
        }
    }

    var title: String {
        switch self {
        case .musicNowPlaying: String(localized: "Show what is playing")
        case .musicLastPlayer: String(localized: "Resume last player")
        case .musicBlockAppleMusic: String(localized: "Stop Apple Music opening on media keys")
        case .spotifyConnect: String(localized: "Spotify Connect speaker")
        case .microphoneMute: String(localized: "Microphone mute")
        case .inUseMarks: String(localized: "In-use marks")
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
        case .archives: String(localized: "Archives")
        case .archivesInPlace: String(localized: "Extract in place")
        case .archivesDefaultApp: String(localized: "Open archives with Notchcast")
        case .torrents: String(localized: "Torrents")
        case .torrentsUseIPhone: String(localized: "Use a plugged-in iPhone for big downloads")
        case .torrentsKeepSharing: String(localized: "Keep sharing until ratio 1.0")
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
        case .musicNowPlaying: String(localized: "Show what is playing")
        case .musicLastPlayer: String(localized: "Resume last player")
        case .musicBlockAppleMusic: String(localized: "Stop Apple Music opening on media keys")
        case .spotifyConnect: String(localized: "Spotify Connect speaker")
        case .microphoneMute: String(localized: "Microphone mute")
        case .inUseMarks: String(localized: "In-use marks")
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
        case .archives: String(localized: "Extract opened archives beside the original file.")
        case .archivesInPlace: String(localized: "The archive shrinks while extracting.")
        case .archivesDefaultApp: String(localized: "Use Notchcast instead of Archive Utility to open archives.")
        case .torrents: String(localized: "Download magnet links and torrent files to Downloads.")
        case .torrentsUseIPhone: String(localized: "Use Wi-Fi and iPhone USB Personal Hotspot together.")
        case .torrentsKeepSharing: String(localized: "Upload as much as you download before stopping.")
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
        case .musicNowPlaying: []
        case .musicLastPlayer: [.accessibility]
        case .musicBlockAppleMusic: [.accessibility]
        case .spotifyConnect: []
        case .microphoneMute: [.accessibility]
        case .inUseMarks: []
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
        case .archives: false
        case .archivesInPlace: false
        case .archivesDefaultApp: false
        case .torrents: false
        case .torrentsUseIPhone: false
        case .torrentsKeepSharing: false
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
