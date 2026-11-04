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
    static let notchcastLauncherTools = Self(tab: .notchcast, title: "Launcher tools")
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
        .init(.notchcastOptions, "GitHub Search", keywords: ["repositories", "stars", "token"]),
        .init(.notchcastOptions, "Clear Notifications", keywords: ["notification center", "accessibility"]),
        .init(.notchcastLauncherTools, "GitHub Token", keywords: ["keychain", "account"]),
        .init(.notchcastOptions, "Currency Answers", keywords: ["nbp", "currency", "rates"]),
        .init(.notchcastOptions, "Copy Path", keywords: ["finder", "browser", "document", "link"]),
        .init(.notchcastOptions, "Small Commands", keywords: ["password", "shorten", "noise", "airdrop"]),
    ]
}
