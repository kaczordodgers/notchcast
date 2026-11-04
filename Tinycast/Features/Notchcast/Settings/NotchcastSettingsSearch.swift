import Foundation

extension SettingsAnchor {
    static let notchcastTweaksApps = Self(tab: .notchcast, title: "System preferences")
    static let notchcastIsland = Self(tab: .notchcast, title: "Island")
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
        .init(.notchcastOptions, "External Displays", keywords: ["monitor", "screen", "display"]),
        .init(.notchcastOptions, "Full-Screen Apps", keywords: ["fullscreen", "full screen", "video"]),
        .init(.notchcastOptions, "Open on Hover", keywords: ["pointer", "mouse", "hover"]),
        .init(.notchcastOptions, "Status Messages", keywords: ["hud", "toast", "message"]),
        .init(.notchcastOptions, "Live Activities", keywords: ["now playing", "timer", "activity"]),
        .init(.notchcastOptions, "Launcher from Island", keywords: ["palette", "search", "open"]),
        .init(.notchcastHover, "Hover delay"),
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
