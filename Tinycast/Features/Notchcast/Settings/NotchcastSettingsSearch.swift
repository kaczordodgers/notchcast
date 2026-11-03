import Foundation

extension SettingsAnchor {
    static let notchcastMonitor = Self(tab: .notchcast, title: LocalizedStringResource("System Monitor"))
    static let notchcastFanMode = Self(tab: .notchcast, title: "Fan mode")
    static let notchcastIsland = Self(tab: .notchcast, title: "Island")
    static let notchcastOptions = Self(tab: .notchcast, title: "Options")
    static let notchcastPermissions = Self(tab: .notchcast, title: "Permissions")
    static let notchcastHover = Self(tab: .notchcast, title: "Island")
    static let notchcastShortcuts = Self(tab: .notchcast, title: LocalizedStringResource("Global Shortcuts"))
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
        .init(.notchcastMonitor, "System Monitor", keywords: ["cpu", "memory", "temperature"]),
        .init(.notchcastMonitor, "Fan Control", keywords: ["cooling", "rpm"]),
        .init(.notchcastFanMode, "Fan mode"),
        .init(group: .notchcastShortcuts, "Toggle Island")
    ]
}
