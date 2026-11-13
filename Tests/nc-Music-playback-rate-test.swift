// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/NowPlayingAdapterReply.swift
// notchcast-sources: Tinycast/Features/Music/Model/NowPlayingAdapterWire.swift
import Foundation

@main
struct PlaybackRateTest {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1000)
        for rate in [0.5, 2.0] {
            let data = try JSONSerialization.data(withJSONObject: [
                "kMRMediaRemoteNowPlayingInfoTitle": "Podcast",
                "kMRMediaRemoteNowPlayingInfoElapsedTime": 10,
                "kMRMediaRemoteNowPlayingInfoPlaybackRate": rate,
                "isPlaying": true
            ])
            guard case .playback(var track, _) = try NowPlayingAdapterReply.parse(data, previous: nil, now: now)
            else { fatalError("Missing track") }
            precondition(track.position(at: now.addingTimeInterval(10)) == 10 + 10 * rate)
            track.isPlaying = false
            precondition(track.position(at: now.addingTimeInterval(10)) == 10)
        }
        print("PASS: playback position respects rate and pause")
    }
}
