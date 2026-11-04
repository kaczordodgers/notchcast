import Foundation

/// One line per anchor and per entry, so branches that add rows merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
extension SettingsAnchor {
    static let notchcastBuildStats = Self(tab: .notchcast, title: "Build statistics")
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
}

extension SettingsSearchCatalog {
    /// Row titles match `NotchcastFeature.title`, which the pane's rows show.
    static let notchcast: [SettingsSearchEntry] = [
        .init(.notchcastBuildStats, "Build statistics", keywords: ["snapshot", "tokens", "quality"]),
        .init(.notchcastSystem, "Machine Setup Profile", keywords: ["backup", "import", "export"]),
        .init(.notchcastMonitor, "Link Quick Fixes", keywords: ["connection", "dns", "repair"]),
        .init(.notchcastAlerts, "Monitor Alerts"),
        .init(.notchcastAlertCPU, "CPU usage threshold"),
        .init(.notchcastAlertTemperature, "CPU temperature threshold"),
        .init(.notchcastAlertMemory, "Memory pressure threshold"),
        .init(.notchcastAlertDisk, "Disk free threshold"),
        .init(.notchcastAlertBattery, "Battery threshold"),
        .init(pane: .notchcast, keywords: ["notch", "island", "dynamic island"]),
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
        .init(.notchcastSystem, "Excluded app bundle IDs (comma-separated)", keywords: ["green button", "maximize", "exceptions"]),
        .init(.notchcastSystem, "Settings Backup", keywords: ["backup", "preferences", "daily"]),
    ]
}
