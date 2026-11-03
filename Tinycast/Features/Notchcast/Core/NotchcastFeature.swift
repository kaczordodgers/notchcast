import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case island, islandExternalDisplays, islandFullScreen, islandHoverOpen
    case islandStatusMessages, islandLiveActivities, launcherFromIsland
    case musicNowPlaying
    case musicLastPlayer
    case musicBlockAppleMusic
    case spotifyConnect
    case microphoneMute
    case inUseMarks

    var defaultOn: Bool { self != .spotifyConnect }

    var dependencies: [Self] {
        switch self {
        case .island: []
        case .musicLastPlayer, .spotifyConnect: [.island, .musicNowPlaying]
        default: [.island]
        }
    }

    var title: String {
        switch self {
        case .island: String(localized: "Island")
        case .islandExternalDisplays: String(localized: "External Displays")
        case .islandFullScreen: String(localized: "Full-Screen Apps")
        case .islandHoverOpen: String(localized: "Open on Hover")
        case .islandStatusMessages: String(localized: "Status Messages")
        case .islandLiveActivities: String(localized: "Live Activities")
        case .launcherFromIsland: String(localized: "Launcher from Island")
        case .musicNowPlaying: String(localized: "Show what is playing")
        case .musicLastPlayer: String(localized: "Resume last player")
        case .musicBlockAppleMusic: String(localized: "Block Apple Music from media keys")
        case .spotifyConnect: String(localized: "Spotify Connect speaker")
        case .microphoneMute: String(localized: "Microphone mute")
        case .inUseMarks: String(localized: "In-use marks")
        }
    }

    var subtitle: String {
        switch self {
        case .island: String(localized: "Show the island at the top of the screen.")
        case .islandExternalDisplays: String(localized: "Show the island on external displays.")
        case .islandFullScreen: String(localized: "Show the island over full-screen apps.")
        case .islandHoverOpen: String(localized: "Open the island when the pointer hovers over it.")
        case .islandStatusMessages: String(localized: "Show status messages in the island.")
        case .islandLiveActivities: String(localized: "Show live activities in the island.")
        case .launcherFromIsland: String(localized: "Open the launcher from the island.")
        case .musicNowPlaying: String(localized: "Show the track and its controls in the island.")
        case .musicLastPlayer: String(localized: "The play key resumes your last app instead of opening Apple Music.")
        case .musicBlockAppleMusic: String(localized: "Quits Apple Music when a media key opens it.")
        case .spotifyConnect: String(localized: "Play Spotify on this Mac from your phone, without the Spotify app.")
        case .microphoneMute: String(localized: "F5 mutes every microphone. Press it again to unmute.")
        case .inUseMarks: String(localized: "Show a mark in the island while the camera or a microphone is on.")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        switch self {
        case .musicLastPlayer, .musicBlockAppleMusic: [.accessibility]
        case .island, .islandExternalDisplays, .islandFullScreen, .islandHoverOpen,
            .islandStatusMessages, .islandLiveActivities, .launcherFromIsland,
            .musicNowPlaying, .spotifyConnect, .microphoneMute, .inUseMarks:
            []
        }
    }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
}
