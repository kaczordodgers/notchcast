import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case island, islandExternalDisplays, islandFullScreen, islandHoverOpen
    case islandStatusMessages, islandLiveActivities, launcherFromIsland
    case musicNowPlaying
    case musicLastPlayer
    case musicBlockAppleMusic
    case spotifyConnect
    case microphoneMute
    case inUseMarks
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
    case torrents
    case torrentsUseIPhone
    case torrentsKeepSharing

    case batteryChargeLimit, batterySailing, batteryHeatProtection, batteryCalibration
    case keepAwake, lidClosedAwake

    case archives, archivesInPlace, archivesDefaultApp

    var defaultOn: Bool {
        self != .spotifyConnect && self != .torrentsKeepSharing && !isSystemFeature
            && self != .archivesInPlace && self != .archivesDefaultApp
    }

    var dependencies: [Self] {
        switch self {
        case .island, .torrents: []
        case .archivesInPlace, .archivesDefaultApp: [.archives]
        case .torrentsUseIPhone, .torrentsKeepSharing: [.torrents]
        case .musicLastPlayer, .spotifyConnect: [.island, .musicNowPlaying]
        default: needsIsland ? [.island] : []
        }
    }

    enum SettingsGroup: Sendable {
        case island, islandOptions, launcher, system, activities, music, archives, torrents
    }

    var settingsGroup: SettingsGroup {
        switch self {
        case .archives, .archivesInPlace, .archivesDefaultApp: .archives
        case .island: .island
        case .islandExternalDisplays, .islandFullScreen, .islandHoverOpen,
             .islandStatusMessages, .islandLiveActivities: .islandOptions
        case .launcherFromIsland: .launcher
        case .systemMonitor, .fanControl, .monitorAlerts, .lowDiskWarning, .systemNotices,
             .volumeLevels, .displayBrightness, .quitProtection, .batteryChargeLimit,
             .batterySailing, .batteryHeatProtection, .batteryCalibration,
             .keepAwake, .lidClosedAwake: .system
        case .liveTimers, .dayWeather, .dayMarkets: .activities
        case .torrents, .torrentsUseIPhone, .torrentsKeepSharing: .torrents
        case .musicNowPlaying, .musicLastPlayer, .musicBlockAppleMusic, .spotifyConnect,
             .microphoneMute, .inUseMarks: .music
        }
    }

    var title: String {
        switch self {
        case .archives: String(localized: "Archives")
        case .archivesInPlace: String(localized: "Extract in place")
        case .archivesDefaultApp: String(localized: "Open archives with Notchcast")
        case .island: String(localized: "Island")
        case .islandExternalDisplays: String(localized: "External Displays")
        case .islandFullScreen: String(localized: "Full-Screen Apps")
        case .islandHoverOpen: String(localized: "Open on Hover")
        case .islandStatusMessages: String(localized: "Status Messages")
        case .islandLiveActivities: String(localized: "Live Activities")
        case .launcherFromIsland: String(localized: "Launcher from Island")
        case .musicNowPlaying: String(localized: "Show what is playing")
        case .musicLastPlayer: String(localized: "Resume last player")
        case .musicBlockAppleMusic: String(localized: "Stop Apple Music opening on media keys")
        case .spotifyConnect: String(localized: "Spotify Connect speaker")
        case .microphoneMute: String(localized: "Microphone mute")
        case .inUseMarks: String(localized: "In-use marks")
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
        case .batteryChargeLimit: String(localized: "Charge Limit")
        case .batterySailing: String(localized: "Battery Sailing")
        case .batteryHeatProtection: String(localized: "Battery Heat Protection")
        case .batteryCalibration: String(localized: "Battery Calibration")
        case .keepAwake: String(localized: "Keep Awake")
        case .lidClosedAwake: String(localized: "Keep Awake with Lid Closed")
        case .torrents: String(localized: "Torrents")
        case .torrentsUseIPhone: String(localized: "Use a plugged-in iPhone for big downloads")
        case .torrentsKeepSharing: String(localized: "Keep sharing until ratio 1.0")
        }
    }

    var subtitle: String {
        switch self {
        case .archives: String(localized: "Extract opened archives beside the original file.")
        case .archivesInPlace: String(localized: "The archive shrinks while extracting.")
        case .archivesDefaultApp: String(localized: "Use Notchcast instead of Archive Utility to open archives.")
        case .island: String(localized: "Show the island at the top of the screen.")
        case .islandExternalDisplays: String(localized: "Show the island on external displays.")
        case .islandFullScreen: String(localized: "Show the island over full-screen apps.")
        case .islandHoverOpen: String(localized: "Open the island when the pointer hovers over it.")
        case .islandStatusMessages: String(localized: "Show status messages in the island.")
        case .islandLiveActivities: String(localized: "Show live activities in the island.")
        case .launcherFromIsland: String(localized: "Open the launcher from the island.")
        case .musicNowPlaying: String(localized: "Show the track and its controls in the island.")
        case .musicLastPlayer: String(localized: "The play key resumes your last app instead of opening Apple Music.")
        case .musicBlockAppleMusic: String(localized: "Quits Apple Music when a media key opens it.")
        case .spotifyConnect: String(localized: "Play Spotify on this Mac from your phone, without the Spotify app.")
        case .microphoneMute: String(localized: "F5 mutes every microphone. Press it again to unmute.")
        case .inUseMarks: String(localized: "Show a mark in the island while the camera or a microphone is on.")
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
        case .batteryChargeLimit: String(localized: "Stop charging at the selected limit.")
        case .batterySailing: String(localized: "Use battery power above the charge limit.")
        case .batteryHeatProtection: String(localized: "Pause charging when the battery is hot.")
        case .batteryCalibration: String(localized: "Run a full battery calibration cycle.")
        case .keepAwake: String(localized: "Prevent idle sleep for the selected duration.")
        case .lidClosedAwake: String(localized: "Keep awake while the lid is closed.")
        case .torrents: String(localized: "Download magnet links and torrent files to Downloads.")
        case .torrentsUseIPhone: String(localized: "Use Wi-Fi and iPhone USB Personal Hotspot together.")
        case .torrentsKeepSharing: String(localized: "Upload as much as you download before stopping.")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        switch self {
        case .archives, .archivesInPlace, .archivesDefaultApp: []
        case .musicLastPlayer, .musicBlockAppleMusic, .microphoneMute,
            .volumeLevels, .displayBrightness, .quitProtection: [.accessibility]
        case .island, .islandExternalDisplays, .islandFullScreen, .islandHoverOpen,
            .islandStatusMessages, .islandLiveActivities, .launcherFromIsland,
            .musicNowPlaying, .spotifyConnect, .inUseMarks,
            .lowDiskWarning, .systemNotices, .liveTimers, .dayWeather, .dayMarkets,
            .systemMonitor, .monitorAlerts, .fanControl, .batteryChargeLimit, .batterySailing,
            .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake,
            .torrents, .torrentsUseIPhone, .torrentsKeepSharing:
            []
        }
    }
}

extension NotchcastFeature {
    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        self != .displayBrightness && self != .quitProtection && !isSystemFeature
            && settingsGroup != .archives && !isTorrentFeature
    }

    var isTorrentFeature: Bool { [.torrents, .torrentsUseIPhone, .torrentsKeepSharing].contains(self) }

    var isSystemFeature: Bool {
        [.systemMonitor, .monitorAlerts, .fanControl, .batteryChargeLimit, .batterySailing,
         .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake].contains(self)
    }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
}
