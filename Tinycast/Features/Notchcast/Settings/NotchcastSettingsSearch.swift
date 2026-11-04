import Foundation

extension SettingsAnchor {
    static let notchcastIsland = Self(tab: .notchcast, title: "Island")
    static let notchcastOptions = Self(tab: .notchcast, title: "Options")
    static let notchcastPermissions = Self(tab: .notchcast, title: "Permissions")
    static let notchcastShortcuts = Self(tab: .notchcast, title: LocalizedStringResource("Global Shortcuts"))
    static let notchcastBrightness = Self(tab: .notchcast, title: "Brightness")
    static let notchcastQuitProtection = Self(tab: .notchcast, title: "Quit protection")
    static let notchcastTimers = Self(tab: .notchcast, title: "Timers")
    static let notchcastDay = Self(tab: .notchcast, title: "Day")
    static let notchcastDownloads = Self(tab: .notchcast, title: "Downloads")
}

extension SettingsSearchCatalog {
    /// Row titles match `NotchcastFeature.title`, which the pane's rows show.
    static let notchcast: [SettingsSearchEntry] = [
        .init(pane: .notchcast, keywords: ["notch", "island", "dynamic island"]),
        .init(.notchcastIsland, "Island", keywords: ["notch", "enable", "dynamic island", "hover delay"]),
        .init(.notchcastOptions, "External Displays", keywords: ["monitor", "screen", "display"]),
        .init(.notchcastOptions, "Full-Screen Apps", keywords: ["fullscreen", "full screen", "video"]),
        .init(.notchcastOptions, "Open on Hover", keywords: ["pointer", "mouse", "hover"]),
        .init(.notchcastOptions, "Status Messages", keywords: ["hud", "toast", "message"]),
        .init(.notchcastOptions, "Live Activities", keywords: ["now playing", "timer", "activity"]),
        .init(.notchcastOptions, "Launcher from Island", keywords: ["palette", "search", "open"]),
        .init(group: .notchcastShortcuts, "Toggle Island"),
        .init(.notchcastOptions, "Display Brightness", keywords: ["display", "dimming", "slider"]),
        .init(.notchcastOptions, "Volume in Island", keywords: ["sound", "microphone", "mute"]),
        .init(.notchcastOptions, "System Notices", keywords: ["wifi", "tailscale", "battery"]),
        .init(.notchcastOptions, "Low Disk Warning", keywords: ["storage", "warning"]),
        .init(.notchcastOptions, "Quit Protection", keywords: ["quit", "hold", "double press", "exceptions"]),
        .init(.notchcastOptions, "Timers", keywords: ["duration", "alarm", "sound"]),
        .init(.notchcastOptions, "Weather", keywords: ["city", "forecast"]),
        .init(.notchcastOptions, "Markets", keywords: ["symbols", "stocks", "prices"]),
        .init(.notchcastOptions, "Downloads", keywords: ["video", "audio", "transcript", "webpage", "clipboard"]),
        .init(.notchcastOptions, "Fast Downloads with aria2c", keywords: ["download", "speed", "aria2"]),
        .init(.notchcastOptions, "Distill", keywords: ["links", "transcribe", "media", "queue"]),
        .init(.notchcastOptions, "Distill Timestamps", keywords: ["transcript", "time", "chunks"]),
        .init(.notchcastOptions, "Convert Distill Folder", keywords: ["markdown", "pdf", "ocr", "files"]),
    ]
}
