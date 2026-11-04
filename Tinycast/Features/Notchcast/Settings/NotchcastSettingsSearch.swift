import Foundation

extension SettingsAnchor {
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
    static let notchcastOptions = Self(tab: .notchcast, title: "Options")
    static let notchcastPermissions = Self(tab: .notchcast, title: "Permissions")
    static let notchcastShortcuts = Self(tab: .notchcast, title: LocalizedStringResource("Global Shortcuts"))
    static let notchcastBrightness = Self(tab: .notchcast, title: "Brightness")
    static let notchcastQuitProtection = Self(tab: .notchcast, title: "Quit protection")
    static let notchcastTimers = Self(tab: .notchcast, title: "Timers")
    static let notchcastDay = Self(tab: .notchcast, title: "Day")
}

extension SettingsSearchCatalog {
    /// Row titles match `NotchcastFeature.title`, which the pane's rows show.
    static let notchcast: [SettingsSearchEntry] = [
        .init(.notchcastAlerts, "Monitor Alerts"),
        .init(.notchcastAlertCPU, "CPU usage threshold"),
        .init(.notchcastAlertTemperature, "CPU temperature threshold"),
        .init(.notchcastAlertMemory, "Memory pressure threshold"),
        .init(.notchcastAlertDisk, "Disk free threshold"),
        .init(.notchcastAlertBattery, "Battery threshold"),
        .init(pane: .notchcast, keywords: ["notch", "island", "dynamic island"]),
        .init(.notchcastIsland, "Island", keywords: ["notch", "enable", "dynamic island", "hover delay"]),
        .init(.notchcastOptions, "External Displays", keywords: ["monitor", "screen", "display"]),
        .init(.notchcastOptions, "Full-Screen Apps", keywords: ["fullscreen", "full screen", "video"]),
        .init(.notchcastOptions, "Open on Hover", keywords: ["pointer", "mouse", "hover"]),
        .init(.notchcastOptions, "Status Messages", keywords: ["hud", "toast", "message"]),
        .init(.notchcastOptions, "Live Activities", keywords: ["now playing", "timer", "activity"]),
        .init(.notchcastOptions, "Launcher from Island", keywords: ["palette", "search", "open"]),
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
        .init(.notchcastOptions, "Display Brightness", keywords: ["display", "dimming", "slider"]),
        .init(.notchcastOptions, "Volume in Island", keywords: ["sound", "microphone", "mute"]),
        .init(.notchcastOptions, "System Notices", keywords: ["wifi", "tailscale", "battery"]),
        .init(.notchcastOptions, "Low Disk Warning", keywords: ["storage", "warning"]),
        .init(.notchcastOptions, "Quit Protection", keywords: ["quit", "hold", "double press", "exceptions"]),
        .init(.notchcastOptions, "Timers", keywords: ["duration", "alarm", "sound"]),
        .init(.notchcastOptions, "Weather", keywords: ["city", "forecast"]),
        .init(.notchcastOptions, "Markets", keywords: ["symbols", "stocks", "prices"]),
    ]
}
