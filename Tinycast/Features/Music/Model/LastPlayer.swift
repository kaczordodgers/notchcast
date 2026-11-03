import Foundation
import Observation

@MainActor
@Observable
final class LastPlayer {
    static let key = "music.lastPlayer"
    static let appleMusic = "com.apple.Music"
    static let spotify = "com.spotify.client"

    private(set) var bundleID: String?
    private(set) var isEnabled = false
    @ObservationIgnored private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let canPlay: (String) -> Bool
    @ObservationIgnored private var playable: [String: Bool] = [:]

    init(defaults: UserDefaults, canPlay: @escaping (String) -> Bool = { $0 == LastPlayer.spotify }) {
        self.defaults = defaults
        self.canPlay = canPlay
        if let saved = defaults.string(forKey: Self.key), Self.canResume(saved) {
            let supported = canPlay(saved)
            playable[saved] = supported
            bundleID = supported ? saved : nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        revision += 1
    }

    func hear(_ track: NowPlaying?) {
        guard isEnabled, let track, track.isPlaying, let id = track.bundleID,
            id != bundleID, Self.canResume(id) else { return }
        let supported = playable[id] ?? canPlay(id)
        playable[id] = supported
        guard supported else { return }
        bundleID = id
        defaults.set(id, forKey: Self.key)
    }

    func replacement(isInstalled: (String) -> Bool) -> String? {
        if let bundleID, isInstalled(bundleID) { return bundleID }
        return isInstalled(Self.spotify) ? Self.spotify : nil
    }

    private static func canResume(_ id: String) -> Bool {
        !id.isEmpty && id != appleMusic && id != "com.apple.iTunes"
    }
}
