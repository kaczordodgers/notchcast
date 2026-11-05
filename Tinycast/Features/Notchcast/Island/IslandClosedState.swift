import AppKit

/// What a closed island shows: the playing song, the activity that outranks the rest, and the next one, which the
/// notch puts in the row under the camera and the island in a bubble (look-decisions, Cards: two at once).
struct IslandClosedState: Equatable {
    struct Music: Equatable {
        var title: String
        var artist: String
        var artwork: NSImage?
        var isPlaying: Bool
    }

    var primary: IslandActivity?
    var secondary: IslandActivity?
    var music: Music?

    var isEmpty: Bool { primary == nil && secondary == nil && music == nil }

    /// An activity outranks a song: the song drops to the second slot, the second activity is not shown.
    var hasSecond: Bool { secondary != nil || (music != nil && primary != nil) }

    /// Beside a camera the band holds two wings only; a button or a second thing takes the row under the camera.
    var needsRow: Bool { hasSecond || primary?.action != nil }

    static func resolve(activities: [IslandActivity], music: Music?) -> Self {
        let ranked = activities.sorted { $0.outranks($1) }
        return Self(primary: ranked.first, secondary: ranked.dropFirst().first, music: music)
    }
}
