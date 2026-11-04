// notchcast-sources: Tinycast/Features/Music/Service/*Module.swift
// notchcast-sources: Tinycast/Features/Microphone/MicrophoneMuteModule.swift
// notchcast-sources: Tinycast/Features/Microphone/InUseMarksModule.swift
import Foundation

@MainActor protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}
enum PlayerCommand: Equatable { case play, togglePlayPause }
@MainActor struct PlayerApps { static func workspace() -> Self { Self() } }
@MainActor final class LastPlayer {
    var enabled = false
    func setEnabled(_ value: Bool) { enabled = value }
}
@MainActor final class MusicModel {
    let lastPlayer = LastPlayer()
    var isEnabled = false
    var nowPlaying: Int?
    init(defaults: UserDefaults, apps: PlayerApps) {}
    func setSystemSource(_ source: SystemNowPlayingSource) {}
    func setSoloistSource(_ source: SoloistSource) {}
    func reportCommandFailure() {}
    func setEnabled(_ value: Bool) { isEnabled = value }
    func send(_ command: PlayerCommand) {}
    func openReplacement(startingPlayback: Bool) -> Task<Void, Never> { Task {} }
}
@MainActor final class SystemNowPlayingSource {
    var onCommandFailure: (() -> Void)?
}
@MainActor final class SoloistSource {
    struct Auth { var loggedIn = false }
    var authState: Auth?
    var isConnected = false
    func send(_ command: PlayerCommand) {}
    func connect(port: Int?) { isConnected = port != nil }
}
@MainActor final class MusicLaunchBlocker {
    var enabled = false
    init(_ replacement: @escaping (Bool) -> Task<Void, Never>) {}
    func setEnabled(_ value: Bool) { enabled = value }
}
@MainActor final class SoloistKey {}
struct SoloistInstaller {}
struct LiveSoloistLauncher {}
struct LiveSoloistProcessList {}
@MainActor final class SoloistSpeaker {
    var onPort: ((Int?) -> Void)?
    var enabled = false
    init(key: SoloistKey, builds: SoloistInstaller, launcher: LiveSoloistLauncher,
         processes: LiveSoloistProcessList, deviceName: String) {}
    func setEnabled(_ value: Bool) { enabled = value }
}
enum MicrophoneInput { enum Failure: Error { case unavailable } }
@MainActor final class MicrophoneMute {
    var failures: [MicrophoneInput.Failure] = []
    var isMuted = false
    var running = false
    func start() { running = true }
    func stop() { running = false }
    func setMuted(_ value: Bool) { isMuted = value }
    func toggle() { isMuted.toggle() }
}
@MainActor final class InUseMarks {
    var enabled = false
    func setEnabled(_ value: Bool) { enabled = value }
}

@main @MainActor struct ModuleLifecycleTests {
    static func main() {
        let suite = "module-lifecycle.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let music = MusicNowPlayingModule(defaults: defaults)
        let last = MusicLastPlayerModule(model: music.model)
        let block = MusicBlockAppleMusicModule(music: music)
        let spotify = SpotifyConnectModule(source: music.soloist, defaults: defaults)
        let mute = MicrophoneMute()
        let microphone = MicrophoneMuteModule(model: mute, showMessage: { _ in }, showFailure: { _ in })
        let marks = InUseMarksModule(model: InUseMarks())
        let modules: [any NotchcastModule] = [music, last, block, spotify, microphone, marks]
        for module in modules { module.start() }
        precondition(music.model.isEnabled && music.model.lastPlayer.enabled && block.blocker.enabled)
        precondition(spotify.isEnabled && spotify.speaker.enabled && microphone.isEnabled && mute.running)
        precondition(marks.model.enabled)
        microphone.setMuted(true)
        precondition(mute.isMuted)
        music.soloist.connect(port: 123)
        for module in modules.reversed() { module.stop() }
        precondition(!music.model.isEnabled && !music.model.lastPlayer.enabled && !block.blocker.enabled)
        precondition(!spotify.isEnabled && !spotify.speaker.enabled && !music.soloist.isConnected)
        precondition(!microphone.isEnabled && !mute.running && !mute.isMuted && !marks.model.enabled)
        print("PASS: all six shipped modules start and stop with offline stubs")
    }
}
