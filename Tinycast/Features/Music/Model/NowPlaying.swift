import Foundation

/// What a player says it is playing. The position is not stored as it moves: `elapsed` was true at
/// `stamp`, and a view runs it on while the track plays.
struct NowPlaying: Equatable, Sendable {
    /// Which engine reported the track, so commands go back to the same one.
    enum Origin: Equatable, Sendable {
        case system
        case soloist
    }

    var title: String
    var artist: String
    var album: String
    /// The player's display name ("Spotify"); the bundle id is how the app is found again.
    var app: String
    var bundleID: String?
    var duration: TimeInterval
    var elapsed: TimeInterval
    var stamp: Date
    var isPlaying: Bool
    var artwork: Data?
    var origin: Origin
    var shuffle: Bool?
    var repeatMode: RepeatMode?

    /// The position at `now`, run on from `stamp` while playing and clamped to the track.
    func position(at now: Date) -> TimeInterval {
        let moved = isPlaying ? max(0, now.timeIntervalSince(stamp)) : 0
        return duration > 0 ? min(duration, elapsed + moved) : elapsed + moved
    }
}

/// What the island, the play key and the CLI ask a player to do.
enum PlayerCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case next
    case previous
    case seek(TimeInterval)
    /// 0...1.
    case volume(Double)
    case shuffle(Bool)
    case `repeat`(RepeatMode)
}

enum RepeatMode: String, Equatable, Sendable {
    case off
    case all
    case one
}

struct MusicQueueItem: Equatable, Sendable {
    var title: String?
    var artist: String?
    var uri: String?
}

/// Where what is playing comes from. `watch` is event-driven: the source calls back after a change,
/// and nothing here polls. A source that cannot be read throws and the model retries with a growing
/// wait.
@MainActor
protocol NowPlayingSource: AnyObject {
    var queue: [MusicQueueItem]? { get }
    func watch(_ onChange: @escaping @MainActor () -> Void)
    func unwatch()
    /// The current track, nil while nothing plays.
    func read() async throws -> NowPlaying?
    func send(_ command: PlayerCommand)
}

extension NowPlayingSource {
    var queue: [MusicQueueItem]? { nil }
}
