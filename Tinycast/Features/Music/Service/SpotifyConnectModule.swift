import Foundation
import Observation

@MainActor
@Observable
final class SpotifyConnectModule: NotchcastModule {
    nonisolated static let deviceNameKey = "spotify.deviceName"
    let key: SoloistKey
    private(set) var speaker: SoloistSpeaker
    private(set) var deviceName: String
    private(set) var isEnabled = false
    @ObservationIgnored private let source: SoloistSource
    @ObservationIgnored private let defaults: UserDefaults

    init(source: SoloistSource, defaults: UserDefaults, key: SoloistKey = SoloistKey()) {
        self.key = key
        self.source = source
        self.defaults = defaults
        let name = defaults.string(forKey: Self.deviceNameKey) ?? "Notchcast"
        deviceName = name
        speaker = Self.makeSpeaker(key: key, source: source, name: name)
    }

    func start() {
        isEnabled = true
        speaker.setEnabled(true)
    }

    func stop() {
        isEnabled = false
        speaker.setEnabled(false)
        source.connect(port: nil)
    }

    func setDeviceName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Notchcast" : trimmed
        guard name != deviceName else { return }
        speaker.onPort = nil
        speaker.setEnabled(false)
        source.connect(port: nil)
        deviceName = name
        defaults.set(name, forKey: Self.deviceNameKey)
        speaker = Self.makeSpeaker(key: key, source: source, name: name)
        speaker.setEnabled(isEnabled)
    }

    private static func makeSpeaker(key: SoloistKey, source: SoloistSource, name: String) -> SoloistSpeaker {
        let speaker = SoloistSpeaker(key: key, builds: SoloistInstaller(), launcher: LiveSoloistLauncher(),
                                     processes: LiveSoloistProcessList(), deviceName: name)
        speaker.onPort = { [weak source] in source?.connect(port: $0) }
        return speaker
    }
}
