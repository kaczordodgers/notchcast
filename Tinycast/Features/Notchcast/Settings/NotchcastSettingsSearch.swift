import Foundation

extension SettingsAnchor {
    static let notchcastIsland = Self(tab: .notchcast, title: "Island")
    static let notchcastExtras = Self(tab: .notchcast, title: "Notchcast")
    static let notchcastOptions = Self(tab: .notchcast, title: "Options")
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
        .init(.notchcastOptions, "Launcher from Island", keywords: ["palette", "search", "open"]),
        .init(.notchcastHover, "Hover delay"),
        .init(group: .notchcastShortcuts, "Toggle Island"),
        .init(.notchcastExtras, "Display Brightness", keywords: ["display", "dimming", "slider"]),
        .init(.notchcastExtras, "Volume in Island", keywords: ["sound", "microphone", "mute"]),
        .init(.notchcastExtras, "System Notices", keywords: ["wifi", "tailscale", "battery"]),
        .init(.notchcastExtras, "Low Disk Warning", keywords: ["storage", "warning"]),
        .init(.notchcastExtras, "Quit Protection", keywords: ["quit", "hold", "double press", "exceptions"]),
        .init(.notchcastExtras, "Timers", keywords: ["duration", "alarm", "sound"]),
        .init(.notchcastExtras, "Calendar", keywords: ["events", "day", "schedule"]),
        .init(.notchcastExtras, "Weather", keywords: ["city", "forecast"]),
        .init(.notchcastExtras, "Markets", keywords: ["symbols", "stocks", "prices"]),
    ]
}
