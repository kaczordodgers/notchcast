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

    init(defaults: UserDefaults) {
        self.defaults = defaults
        bundleID = defaults.string(forKey: Self.key).flatMap { Self.canResume($0) ? $0 : nil }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        revision += 1
    }

    func hear(_ track: NowPlaying?) {
        guard isEnabled, let track, track.isPlaying, let id = track.bundleID,
            Self.canResume(id), id != bundleID else { return }
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
