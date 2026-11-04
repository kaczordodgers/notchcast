import Foundation

extension SettingsAnchor {
    static let notchcastTweaksApps = Self(tab: .notchcast, title: "System preferences")
    static let notchcastAlerts = Self(tab: .notchcast, title: LocalizedStringResource("Monitor Alerts"))
    static let notchcastAlertCPU = Self(tab: .notchcast, title: "CPU usage threshold")
    static let notchcastAlertTemperature = Self(tab: .notchcast, title: "CPU temperature threshold")
    static let notchcastAlertMemory = Self(tab: .notchcast, title: "Memory pressure threshold")
    static let notchcastAlertDisk = Self(tab: .notchcast, title: "Disk free threshold")
    static let notchcastAlertBattery = Self(tab: .notchcast, title: "Battery threshold")
    static let notchcastChargePercent = Self(tab: .notchcast, title: "Charge limit percent")
    static let notchcastAwakeDuration = Self(tab: .notchcast, title: "Keep-awake duration")
    static let notchcastMonitor = Self(tab: .notchcast, title: LocalizedStringResource("System Monitor"))
    static let notchcastFanMode = Self(tab: .notchcast, title: "Fan mode")
    static let notchcastIsland = Self(tab: .notchcast, title: "Island")
    static let notchcastOptions = Self(tab: .notchcast, title: LocalizedStringResource("Island Options"))
    static let notchcastLauncher = Self(tab: .notchcast, title: "Launcher")
    static let notchcastSystem = Self(tab: .notchcast, title: "System")
    static let notchcastActivities = Self(tab: .notchcast, title: "Activities")
    static let notchcastPermissions = Self(tab: .notchcast, title: "Permissions")
    static let notchcastShortcuts = Self(tab: .notchcast, title: LocalizedStringResource("Global Shortcuts"))
    static let notchcastBrightness = Self(tab: .notchcast, title: "Brightness")
    static let notchcastQuitProtection = Self(tab: .notchcast, title: LocalizedStringResource("Quit Protection"))
    static let notchcastTimers = Self(tab: .notchcast, title: "Timers")
    static let notchcastDay = Self(tab: .notchcast, title: "Day")
    static let notchcastTweaks = Self(tab: .notchcast, title: "Tweaks")
}

extension SettingsSearchCatalog {
    /// Row titles match `NotchcastFeature.title`, which the pane's rows show.
    static let notchcast: [SettingsSearchEntry] = [
        .init(.notchcastSystem, "Machine Setup Profile", keywords: ["backup", "import", "export"]),
        .init(.notchcastMonitor, "Link Quick Fixes", keywords: ["connection", "dns", "repair"]),
        .init(.notchcastAlerts, "Monitor Alerts"),
        .init(.notchcastAlertCPU, "CPU usage threshold"),
        .init(.notchcastAlertTemperature, "CPU temperature threshold"),
        .init(.notchcastAlertMemory, "Memory pressure threshold"),
        .init(.notchcastAlertDisk, "Disk free threshold"),
        .init(.notchcastAlertBattery, "Battery threshold"),
        .init(pane: .notchcast, keywords: ["notch", "island", "dynamic island"]),
        .init(.notchcastTweaksApps, "Disable autocorrect"),
        .init(.notchcastTweaksApps, "Disable smart punctuation"),
        .init(.notchcastTweaksApps, "Disable double-space period"),
        .init(.notchcastTweaksApps, "Disable auto-capitalization"),
        .init(.notchcastTweaksApps, "Enable key repeat"),
        .init(.notchcastTweaksApps, "Show file extensions"),
        .init(.notchcastTweaksApps, "Show hidden files"),
        .init(.notchcastTweaksApps, "Show path bar"),
        .init(.notchcastTweaksApps, "Show status bar"),
        .init(.notchcastTweaksApps, "Keep folders first"),
        .init(.notchcastTweaksApps, "Search current folder"),
        .init(.notchcastTweaksApps, "Disable extension warning"),
        .init(.notchcastTweaksApps, "Show path in title"),
        .init(.notchcastTweaksApps, "Avoid network metadata"),
        .init(.notchcastTweaksApps, "Remove trash after 30 days"),
        .init(.notchcastTweaksApps, "Save locally"),
        .init(.notchcastTweaksApps, "Expand save dialogs"),
        .init(.notchcastTweaksApps, "Use list view"),
        .init(.notchcastTweaksApps, "Avoid USB metadata"),
        .init(.notchcastTweaksApps, "Hide desktop disks"),
        .init(.notchcastTweaksApps, "Hide recent apps"),
        .init(.notchcastTweaksApps, "Remove auto-hide delay"),
        .init(.notchcastTweaksApps, "Disable launch animation"),
        .init(.notchcastTweaksApps, "Minimize into app"),
        .init(.notchcastTweaksApps, "Disable window animations"),
        .init(.notchcastTweaksApps, "Remove tiled window margins"),
        .init(.notchcastTweaksApps, "Remove screenshot shadow"),
        .init(.notchcastTweaksApps, "Disable click to desktop"),
        .init(.notchcastTweaksApps, "Hide desktop widgets"),
        .init(.notchcastTweaksApps, "Typing"),
        .init(.notchcastTweaksApps, "Show library"),
        .init(.notchcastTweaksApps, "Restrict gaming"),
        .init(.notchcastTweaksApps, "Restrict iPhone mirroring"),
        .init(.notchcastTweaksApps, "Restrict music service"),
        .init(.notchcastTweaksApps, "Restrict book store"),
        .init(.notchcastTweaksApps, "Finder"),
        .init(.notchcastTweaksApps, "Dock and windows"),
        .init(.notchcastTweaksApps, "Apple apps"),
        .init(.notchcastTweaksApps, "iPhone backup"),
        .init(.notchcastTweaksApps, "Key repeat speed"),
        .init(.notchcastTweaksApps, "Key repeat delay"),
        .init(.notchcastTweaksApps, "New Finder windows"),
        .init(.notchcastTweaksApps, "Disable automatic iPhone backups"),
        .init(.notchcastTweaksApps, "iPhone backup folder"),
        .init(.notchcastIsland, "Island", keywords: ["notch", "enable", "dynamic island"]),
        .init(.notchcastOptions, "External Displays", keywords: ["monitor", "screen", "display", "hover delay"]),
        .init(.notchcastOptions, "Full-Screen Apps", keywords: ["fullscreen", "full screen", "video"]),
        .init(.notchcastOptions, "Open on Hover", keywords: ["pointer", "mouse", "hover"]),
        .init(.notchcastOptions, "Status Messages", keywords: ["hud", "toast", "message"]),
        .init(.notchcastOptions, "Live Activities", keywords: ["now playing", "timer", "activity"]),
        .init(.notchcastLauncher, "Launcher from Island", keywords: ["palette", "search", "open"]),
        .init(.notchcastLauncher, "Launcher Number Keys", keywords: ["command", "results", "1", "9"]),
        .init(.notchcastLauncher, "Alias and Space", keywords: ["alias", "space", "arguments"]),
        .init(.notchcastMonitor, "System Monitor", keywords: ["cpu", "memory", "temperature"]),
        .init(.notchcastMonitor, "Fan Control", keywords: ["cooling", "rpm"]),
        .init(.notchcastFanMode, "Fan mode"),
        .init(.notchcastMonitor, "Charge Limit"),
        .init(.notchcastMonitor, "Battery Sailing"),
        .init(.notchcastMonitor, "Battery Heat Protection"),
        .init(.notchcastMonitor, "Battery Calibration"),
        .init(.notchcastMonitor, "Keep Awake"),
        .init(.notchcastMonitor, "Keep Awake with Lid Closed"),
        .init(.notchcastChargePercent, "Charge limit percent"),
        .init(.notchcastAwakeDuration, "Keep-awake duration"),
        .init(group: .notchcastShortcuts, "Toggle Island"),
        .init(.notchcastSystem, "Display Brightness", keywords: ["display", "dimming", "slider"]),
        .init(.notchcastSystem, "Volume in Island", keywords: ["sound", "microphone", "mute"]),
        .init(.notchcastSystem, "System Notices", keywords: ["wifi", "tailscale", "battery"]),
        .init(.notchcastSystem, "Low Disk Warning", keywords: ["storage", "warning"]),
        .init(.notchcastSystem, "Quit Protection", keywords: ["quit", "hold", "double press", "exceptions"]),
        .init(.notchcastActivities, "Timers", keywords: ["duration", "alarm", "sound"]),
        .init(.notchcastActivities, "Calendar", keywords: ["events", "day", "schedule"]),
        .init(.notchcastActivities, "Weather", keywords: ["city", "forecast"]),
        .init(.notchcastActivities, "Markets", keywords: ["symbols", "stocks", "prices"]),
        .init(.notchcastSystem, "Green Button Maximizes", keywords: ["window", "maximize", "restore"]),
        .init(.notchcastSystem, "Trackpad Middle Click", keywords: ["three finger", "mouse", "trackpad"]),
        .init(.notchcastSystem, "Show Desktop with F3", keywords: ["mission control", "windows"]),
        .init(.notchcastSystem, "Hide with ⌘M", keywords: ["minimize", "command m"]),
        .init(.notchcastSystem, "Keep Spaces in a fixed order", keywords: ["desktop", "reorder"]),
        .init(.notchcastSystem, "Excluded app bundle IDs (comma-separated)",
              keywords: ["green button", "maximize", "exceptions"]),
        .init(.notchcastSystem, "Settings Backup", keywords: ["backup", "preferences", "daily"]),
    ] + NotchcastFeature.systemToolsSettingsFeatures.map {
        switch $0 {
        case .startupItems: SettingsSearchEntry(.notchcastTweaks, "Startup Items", keywords: ["launchagents"])
        case .notificationCleanup: SettingsSearchEntry(.notchcastTweaks, "Notification Cleanup", keywords: ["disk", "ejection"])
        case .sudoTouchID: SettingsSearchEntry(.notchcastTweaks, "Touch ID for sudo", keywords: ["authentication"])
        default: SettingsSearchEntry(.notchcastTweaks, "Spotlight Indexing Off", keywords: ["search"])
        }
    }
}
