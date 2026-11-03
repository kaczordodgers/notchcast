import Foundation

extension SettingsAnchor {
    static let notchcastIsland = Self(tab: .notchcast, title: "Island")
    static let notchcastOptions = Self(tab: .notchcast, title: "Island options")
    static let notchcastLauncher = Self(tab: .notchcast, title: "Launcher")
    static let notchcastSystem = Self(tab: .notchcast, title: "System")
    static let notchcastActivities = Self(tab: .notchcast, title: "Activities")
    static let notchcastPermissions = Self(tab: .notchcast, title: "Permissions")
    static let notchcastHover = Self(tab: .notchcast, title: "Island")
    static let notchcastShortcuts = Self(tab: .notchcast, title: LocalizedStringResource("Global Shortcuts"))
    static let notchcastBrightness = Self(tab: .notchcast, title: "Brightness")
    static let notchcastQuitProtection = Self(tab: .notchcast, title: "Quit protection")
    static let notchcastTimers = Self(tab: .notchcast, title: "Timers")
    static let notchcastDay = Self(tab: .notchcast, title: "Day")
}

extension SettingsSearchCatalog {
    /// Row titles match `NotchcastFeature.title`, which the pane's rows show.
    static let notchcast: [SettingsSearchEntry] = [
        .init(pane: .notchcast, keywords: ["notch", "island", "dynamic island"]),
        .init(.notchcastIsland, "Island", keywords: ["notch", "enable", "dynamic island"]),
        .init(.notchcastOptions, "External Displays", keywords: ["monitor", "screen", "display"]),
        .init(.notchcastOptions, "Full-Screen Apps", keywords: ["fullscreen", "full screen", "video"]),
        .init(.notchcastOptions, "Open on Hover", keywords: ["pointer", "mouse", "hover"]),
        .init(.notchcastOptions, "Status Messages", keywords: ["hud", "toast", "message"]),
        .init(.notchcastOptions, "Live Activities", keywords: ["now playing", "timer", "activity"]),
        .init(.notchcastLauncher, "Launcher from Island", keywords: ["palette", "search", "open"]),
        .init(.notchcastHover, "Hover delay"),
        .init(group: .notchcastShortcuts, "Toggle Island"),
        .init(.notchcastSystem, "Display Brightness", keywords: ["display", "dimming", "slider"]),
        .init(.notchcastSystem, "Volume in Island", keywords: ["sound", "microphone", "mute"]),
        .init(.notchcastSystem, "System Notices", keywords: ["wifi", "tailscale", "battery"]),
        .init(.notchcastSystem, "Low Disk Warning", keywords: ["storage", "warning"]),
        .init(.notchcastSystem, "Quit Protection", keywords: ["quit", "hold", "double press", "exceptions"]),
        .init(.notchcastActivities, "Timers", keywords: ["duration", "alarm", "sound"]),
        .init(.notchcastActivities, "Weather", keywords: ["city", "forecast"]),
        .init(.notchcastActivities, "Markets", keywords: ["symbols", "stocks", "prices"]),
    ]
}
