import Foundation

// Compiled into both the app and the adapter dylib, so the two ends cannot drift.
enum NowPlayingAdapterWire {
    static let maximumArtworkBytes = 12 * 1_024 * 1_024

    static let error = "error"
    static let sent = "sent"
    static let pid = "pid"
    static let isPlaying = "isPlaying"
    static let displayID = "displayID"
    static let displayName = "displayName"
    static let artworkBase64 = "artworkBase64"
    static let artworkUnchanged = "artworkUnchanged"

    enum Info: String, CaseIterable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case duration = "Duration"
        case elapsedTime = "ElapsedTime"
        case playbackRate = "PlaybackRate"
        case shuffleMode = "ShuffleMode"
        case repeatMode = "RepeatMode"

        var key: String { "kMRMediaRemoteNowPlayingInfo" + rawValue }
    }
}
