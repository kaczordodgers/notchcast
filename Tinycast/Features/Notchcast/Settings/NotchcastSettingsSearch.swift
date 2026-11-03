import Foundation

extension SettingsAnchor {
    static let notchcastIsland = Self(tab: .notchcast, title: "Island")
    static let notchcastOptions = Self(tab: .notchcast, title: "Options")
    static let notchcastPermissions = Self(tab: .notchcast, title: "Permissions")
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
        .init(.notchcastOptions, "External displays", keywords: ["monitor", "screen", "display"]),
        .init(.notchcastOptions, "Full-screen apps", keywords: ["fullscreen", "full screen", "video"]),
        .init(.notchcastOptions, "Open on hover", keywords: ["pointer", "mouse", "hover"]),
        .init(.notchcastOptions, "Status messages", keywords: ["hud", "toast", "message"]),
        .init(.notchcastOptions, "Live activities", keywords: ["now playing", "timer", "activity"]),
        .init(.notchcastOptions, "Launcher from island", keywords: ["palette", "search", "open"]),
        .init(.notchcastOptions, "Display brightness", keywords: ["display", "dimming", "slider"]),
        .init(.notchcastOptions, "Volume in island", keywords: ["sound", "microphone", "mute"]),
        .init(.notchcastOptions, "System notices", keywords: ["wifi", "tailscale", "battery"]),
        .init(.notchcastOptions, "Low disk warning", keywords: ["storage", "warning"]),
        .init(.notchcastOptions, "Quit protection", keywords: ["quit", "hold", "double press", "exceptions"]),
        .init(.notchcastOptions, "Timers", keywords: ["duration", "alarm", "sound"]),
        .init(.notchcastOptions, "Weather", keywords: ["city", "forecast"]),
        .init(.notchcastOptions, "Markets", keywords: ["symbols", "stocks", "prices"]),
    ]
}
