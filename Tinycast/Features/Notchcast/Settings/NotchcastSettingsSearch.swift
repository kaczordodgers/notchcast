import Foundation

/// One line per anchor and per entry, so branches that add rows merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
extension SettingsAnchor {
    static let notchcastAlerts = Self(tab: .notchcast, title: LocalizedStringResource("Monitor Alerts", table: "Notchcast"))
    static let notchcastAlertCPU = Self(tab: .notchcast, title: LocalizedStringResource("CPU usage threshold", table: "Notchcast"))
    static let notchcastAlertTemperature = Self(tab: .notchcast, title: LocalizedStringResource("CPU temperature threshold", table: "Notchcast"))
    static let notchcastAlertMemory = Self(tab: .notchcast, title: LocalizedStringResource("Memory pressure threshold", table: "Notchcast"))
    static let notchcastAlertDisk = Self(tab: .notchcast, title: LocalizedStringResource("Disk free threshold", table: "Notchcast"))
    static let notchcastAlertBattery = Self(tab: .notchcast, title: LocalizedStringResource("Battery threshold", table: "Notchcast"))
    static let notchcastChargePercent = Self(tab: .notchcast, title: LocalizedStringResource("Charge limit percent", table: "Notchcast"))
    static let notchcastAwakeDuration = Self(tab: .notchcast, title: LocalizedStringResource("Keep-awake duration", table: "Notchcast"))
    static let notchcastMonitor = Self(tab: .notchcast, title: LocalizedStringResource("System Monitor", table: "Notchcast"))
    static let notchcastFanMode = Self(tab: .notchcast, title: LocalizedStringResource("Fan mode", table: "Notchcast"))
    static let notchcastIsland = Self(tab: .notchcast, title: LocalizedStringResource("Island", table: "Notchcast"))
    static let notchcastOptions = Self(tab: .notchcast, title: LocalizedStringResource("Island Options", table: "Notchcast"))
    static let notchcastLauncher = Self(tab: .notchcast, title: "Launcher")
    static let notchcastSystem = Self(tab: .notchcast, title: "System")
    static let notchcastActivities = Self(tab: .notchcast, title: LocalizedStringResource("Activities", table: "Notchcast"))
    static let notchcastPermissions = Self(tab: .notchcast, title: "Permissions")
    static let notchcastShortcuts = Self(tab: .notchcast, title: LocalizedStringResource("Global Shortcuts"))
    static let notchcastBrightness = Self(tab: .notchcast, title: LocalizedStringResource("Brightness", table: "Notchcast"))
    static let notchcastQuitProtection = Self(tab: .notchcast, title: LocalizedStringResource("Quit Protection", table: "Notchcast"))
    static let notchcastTimers = Self(tab: .notchcast, title: LocalizedStringResource("Timers", table: "Notchcast"))
    static let notchcastDay = Self(tab: .notchcast, title: LocalizedStringResource("Day", table: "Notchcast"))
}

extension SettingsSearchCatalog {
    /// Row titles match `NotchcastFeature.title`, which the pane's rows show.
    static let notchcast: [SettingsSearchEntry] = [
        .init(.notchcastSystem, LocalizedStringResource("Machine Setup Profile", table: "Notchcast"), keywords: ["backup", "import", "export"]),
        .init(.notchcastMonitor, LocalizedStringResource("Link Quick Fixes", table: "Notchcast"), keywords: ["connection", "dns", "repair"]),
        .init(.notchcastAlerts, LocalizedStringResource("Monitor Alerts", table: "Notchcast")),
        .init(.notchcastAlertCPU, LocalizedStringResource("CPU usage threshold", table: "Notchcast")),
        .init(.notchcastAlertTemperature, LocalizedStringResource("CPU temperature threshold", table: "Notchcast")),
        .init(.notchcastAlertMemory, LocalizedStringResource("Memory pressure threshold", table: "Notchcast")),
        .init(.notchcastAlertDisk, LocalizedStringResource("Disk free threshold", table: "Notchcast")),
        .init(.notchcastAlertBattery, LocalizedStringResource("Battery threshold", table: "Notchcast")),
        .init(pane: .notchcast, keywords: ["notch", "island", "dynamic island"]),
        .init(.notchcastIsland, LocalizedStringResource("Island", table: "Notchcast"), keywords: ["notch", "enable", "dynamic island"]),
        .init(.notchcastOptions, LocalizedStringResource("External Displays", table: "Notchcast"), keywords: ["monitor", "screen", "display", "hover delay"]),
        .init(.notchcastOptions, LocalizedStringResource("Full-Screen Apps", table: "Notchcast"), keywords: ["fullscreen", "full screen", "video"]),
        .init(.notchcastOptions, LocalizedStringResource("Open on Hover", table: "Notchcast"), keywords: ["pointer", "mouse", "hover"]),
        .init(.notchcastOptions, LocalizedStringResource("Status Messages", table: "Notchcast"), keywords: ["hud", "toast", "message"]),
        .init(.notchcastOptions, LocalizedStringResource("Live Activities", table: "Notchcast"), keywords: ["now playing", "timer", "activity"]),
        .init(.notchcastLauncher, LocalizedStringResource("Launcher from Island", table: "Notchcast"), keywords: ["palette", "search", "open"]),
        .init(.notchcastLauncher, LocalizedStringResource("Launcher Number Keys", table: "Notchcast"), keywords: ["command", "results", "1", "9"]),
        .init(.notchcastLauncher, LocalizedStringResource("Alias and Space", table: "Notchcast"), keywords: ["alias", "space", "arguments"]),
        .init(.notchcastMonitor, LocalizedStringResource("System Monitor", table: "Notchcast"), keywords: ["cpu", "memory", "temperature"]),
        .init(.notchcastMonitor, LocalizedStringResource("Fan Control", table: "Notchcast"), keywords: ["cooling", "rpm"]),
        .init(.notchcastFanMode, LocalizedStringResource("Fan mode", table: "Notchcast")),
        .init(.notchcastMonitor, LocalizedStringResource("Charge Limit", table: "Notchcast")),
        .init(.notchcastMonitor, LocalizedStringResource("Battery Sailing", table: "Notchcast")),
        .init(.notchcastMonitor, LocalizedStringResource("Battery Heat Protection", table: "Notchcast")),
        .init(.notchcastMonitor, LocalizedStringResource("Battery Calibration", table: "Notchcast")),
        .init(.notchcastMonitor, LocalizedStringResource("Keep Awake", table: "Notchcast")),
        .init(.notchcastMonitor, LocalizedStringResource("Keep Awake with Lid Closed", table: "Notchcast")),
        .init(.notchcastChargePercent, LocalizedStringResource("Charge limit percent", table: "Notchcast")),
        .init(.notchcastAwakeDuration, LocalizedStringResource("Keep-awake duration", table: "Notchcast")),
        .init(group: .notchcastShortcuts, LocalizedStringResource("Toggle Island", table: "Notchcast")),
        .init(.notchcastSystem, LocalizedStringResource("Display Brightness", table: "Notchcast"), keywords: ["display", "dimming", "slider"]),
        .init(.notchcastSystem, LocalizedStringResource("Volume in Island", table: "Notchcast"), keywords: ["sound", "microphone", "mute"]),
        .init(.notchcastSystem, LocalizedStringResource("System Notices", table: "Notchcast"), keywords: ["wifi", "tailscale", "battery"]),
        .init(.notchcastSystem, LocalizedStringResource("Low Disk Warning", table: "Notchcast"), keywords: ["storage", "warning"]),
        .init(.notchcastSystem, LocalizedStringResource("Quit Protection", table: "Notchcast"), keywords: ["quit", "hold", "double press", "exceptions"]),
        .init(.notchcastActivities, LocalizedStringResource("Timers", table: "Notchcast"), keywords: ["duration", "alarm", "sound"]),
        .init(.notchcastActivities, "Calendar", keywords: ["events", "day", "schedule"]),
        .init(.notchcastActivities, "Weather", keywords: ["city", "forecast"]),
        .init(.notchcastActivities, LocalizedStringResource("Markets", table: "Notchcast"), keywords: ["symbols", "stocks", "prices"]),
        .init(.notchcastSystem, LocalizedStringResource("Green Button Maximizes", table: "Notchcast"), keywords: ["window", "maximize", "restore"]),
        .init(.notchcastSystem, LocalizedStringResource("Trackpad Middle Click", table: "Notchcast"), keywords: ["three finger", "mouse", "trackpad"]),
        .init(.notchcastSystem, LocalizedStringResource("Show Desktop with F3", table: "Notchcast"), keywords: ["mission control", "windows"]),
        .init(.notchcastSystem, LocalizedStringResource("Hide with ⌘M", table: "Notchcast"), keywords: ["minimize", "command m"]),
        .init(.notchcastSystem, LocalizedStringResource("Keep Spaces in a fixed order", table: "Notchcast"), keywords: ["desktop", "reorder"]),
        .init(.notchcastSystem, LocalizedStringResource("Excluded app bundle IDs (comma-separated)", table: "Notchcast"), keywords: ["green button", "maximize", "exceptions"]),
        .init(.notchcastSystem, LocalizedStringResource("Settings Backup", table: "Notchcast"), keywords: ["backup", "preferences", "daily"]),
    ]
}
