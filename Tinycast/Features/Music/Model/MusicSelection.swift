import Foundation

enum MusicSelection {
    static func pick(system: NowPlaying?, soloist: NowPlaying?) -> NowPlaying? {
        let other = system.flatMap { isSoloist($0) ? nil : $0 }
        if let other, other.isPlaying { return other }
        return soloist ?? other
    }

    private static func isSoloist(_ track: NowPlaying) -> Bool {
        track.bundleID == nil && track.app.lowercased() == "soloist"
    }
}
