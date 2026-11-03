import Foundation

extension SettingsAnchor {
    static let notchcastIsland = Self(tab: .notchcast, title: "Island")
    static let notchcastOptions = Self(tab: .notchcast, title: "Options")
    static let notchcastMusic = Self(tab: .notchcast, title: "Music")
    // ai-design-check-ignore-next-line sentence-case -- Spotify Connect is a product name.
    static let notchcastSpotify = Self(tab: .notchcast, title: "Spotify Connect")
    static let notchcastMicrophone = Self(tab: .notchcast, title: "Microphone")
    static let notchcastPermissions = Self(tab: .notchcast, title: "Permissions")
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
        .init(.notchcastMusic, "Show what is playing", keywords: ["now playing", "track", "cover", "media", "song"]),
        .init(.notchcastMusic, "Resume last player", keywords: ["play key", "spotify", "media key"]),
        .init(.notchcastMusic, "Block Apple Music from media keys", keywords: ["music app", "itunes", "media key", "play key"]),
        .init(.notchcastSpotify, "Spotify Connect speaker", keywords: ["soloist", "spotify", "speaker", "connect", "phone"]),
        .init(.notchcastSpotify, "API key", keywords: ["soloist", "key", "developer"]),
        .init(.notchcastSpotify, "Device name", keywords: ["soloist", "speaker name"]),
        .init(group: .notchcastSpotify, "Download Soloist", keywords: ["soloist", "update", "build", "expiry"]),
        .init(.notchcastMicrophone, "Microphone mute", keywords: ["mute", "f5", "mic"]),
        .init(.notchcastMicrophone, "In-use marks", keywords: ["camera", "privacy", "indicator", "recording"])
    ]
}
