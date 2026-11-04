// notchcast-sources: Tinycast/Features/Music/Model/*.swift
// notchcast-sources: Tinycast/Features/Music/Service/*.swift
// notchcast-sources: Tinycast/Features/Music/Commands/*.swift
// notchcast-sources: Tinycast/Features/Microphone/Model/*.swift
// notchcast-sources: Tinycast/Features/Microphone/Service/*.swift
// notchcast-sources: Tinycast/Features/Microphone/Commands/*.swift
// notchcast-sources: Tinycast/Features/Microphone/MicrophoneMuteModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
import AppKit
enum SettingsTab: Sendable { case notchcast }
struct AppEntry: Sendable {
 let id: String
 let name: String
 let url: URL
 let bundleID: String?
 enum Kind: Sendable { case command }
 let kind: Kind
 let settingsOwner: SettingsTab?
 let symbolName: String?
}

@MainActor final class AppCore {
 static let shared = AppCore()
 enum Tone { case danger, success }
 enum Target { case section(Anchor) }
 enum Anchor { case notchcastSpotify }
 let settingsCoordinator = Settings()
 final class Settings {
     var opens = 0
     func showSettings(tab: SettingsTab, revealing: Target) { opens += 1 }
 }
 let appIndex = AppIndex()
 var messages: [String] = []
 func showMessage(_ message: String, tone: Tone = .success) { messages.append(message) }
}
@MainActor final class AppIndex {
 var refreshes = 0
 func refreshNotchcastCommands() { refreshes += 1 }
}
@MainActor enum NotchcastCore {
 static var services: Services?
 struct Services {
 let music: MusicNowPlayingModule
 let microphone: MicrophoneMuteModule
 }
}
@MainActor final class CommandSource: NowPlayingSource {
    var commands: [PlayerCommand] = []
    func watch(_ onChange: @escaping @MainActor () -> Void) {}
    func unwatch() {}
    func read() async throws -> NowPlaying? {
        NowPlaying(title: "Track", artist: "Artist", album: "Album", app: "Player", bundleID: "fixture",
                   duration: 100, elapsed: 0, stamp: .now, isPlaying: false, origin: .system)
    }
    func send(_ command: PlayerCommand) { commands.append(command) }
}

@MainActor final class CommandAudio: MicrophoneAudioAccess {
    var monitoringFailure: MicrophoneInput.Failure?
    var input = MicrophoneInput(id: 1, uid: "fixture", mute: [.init(element: 0, value: 0)], volume: [])
    func inputs() throws(MicrophoneInput.Failure) -> [MicrophoneInput] { [input] }
    func write(_ levels: [MicrophoneInput.Level], control: MicrophoneInput.Control,
               on input: MicrophoneInput) throws(MicrophoneInput.Failure) { self.input.mute = levels }
    func start(change: @escaping @MainActor () -> Void) {}
    func stop() {}
}

@main @MainActor struct MusicCommandTests {
 static func main() async {
 let preferences = NotchcastPreferences.shared
 let suite = "music-command-test.\(UUID())"
 let defaults = UserDefaults(suiteName: suite)!
 defer { defaults.removePersistentDomain(forName: suite) }
 let originalMusic = preferences.isOn(.musicNowPlaying)
 let originalMic = preferences.isOn(.microphoneMute)
 let originalIsland = preferences.isOn(.island)
 defer {
 preferences.set(.musicNowPlaying, originalMusic)
 preferences.set(.microphoneMute, originalMic)
 preferences.set(.island, originalIsland)
 }
 preferences.set(.island, true)
 preferences.set(.musicNowPlaying, true)
 preferences.set(.microphoneMute, true)
 let apps = PlayerApps(isInstalled: { _ in false }, isRunning: { _ in false },
 open: { _ in }, play: { _ in }, watchLaunches: { _ in [] }, quit: { _ in true })
 let music = MusicNowPlayingModule(defaults: defaults, apps: apps)
 defaults.set(LastPlayer.spotify, forKey: LastPlayer.key)
 let resumable = MusicModel(defaults: defaults, apps: PlayerApps(
 isInstalled: { _ in true }, isRunning: { _ in false }, open: { _ in }, play: { _ in },
 watchLaunches: { _ in [] }, quit: { _ in true }))
 resumable.lastPlayer.setEnabled(true)
 precondition(resumable.canResume)
 resumable.lastPlayer.setEnabled(false)
 precondition(!resumable.canResume, "saved installed player requires Resume last player enabled")
 let observer = MusicCommandFeedback(music: music, preferences: preferences)
 defer { withExtendedLifetime(observer) {} }
 let source = CommandSource()
 music.model.setSystemSource(source)
 music.model.setSoloistSource(nil)
 music.start()
 for _ in 0..<100 { await Task.yield() }
 let mute = MicrophoneMute(audio: CommandAudio(), defaults: defaults)
 let microphone = MicrophoneMuteModule(model: mute, showMessage: { _ in }, showFailure: { _ in })
 microphone.start()
 NotchcastCore.services = .init(music: music, microphone: microphone)
 let muteCommands = [MicrophoneMuteCommands.muteLauncherCommand, MicrophoneMuteCommands.unmuteLauncherCommand]
 precondition(muteCommands.allSatisfy { $0.isEnabled() })
 muteCommands[0].run()
 precondition(mute.isMuted)
 muteCommands[1].run()
 precondition(!mute.isMuted)
 for feature: NotchcastFeature in [.microphoneMute, .island] {
     preferences.set(feature, false)
     precondition(muteCommands.allSatisfy { !$0.isEnabled() })
     muteCommands[0].run()
     precondition(!mute.isMuted)
     microphone.setMuted(true)
     muteCommands[1].run()
     precondition(mute.isMuted)
     microphone.setMuted(false)
     preferences.set(feature, true)
 }
 defer { music.stop(); microphone.stop(); NotchcastCore.services = nil }
 let commands = MusicCommands.launcherCommands
 precondition(commands.map(\.id) == ["command:nc-open-current-player"])
 precondition(commands.allSatisfy { $0.isEnabled() })
 for command: PlayerCommand in [.togglePlayPause, .next, .previous] { MusicCommands.send(command) }
 precondition(source.commands == [.togglePlayPause, .next, .previous])
 let savedSpeaker = preferences.isOn(.spotifyConnect)
 let savedResume = preferences.isOn(.musicLastPlayer)
 defer {
     preferences.set(.spotifyConnect, savedSpeaker)
     preferences.set(.musicLastPlayer, savedResume)
 }
 preferences.set(.spotifyConnect, false)
 let opens = AppCore.shared.settingsCoordinator.opens
 MusicCommands.speakerOnCommand.run()
 precondition(!preferences.isOn(.spotifyConnect))
 precondition(AppCore.shared.settingsCoordinator.opens == opens + 1)
 preferences.set(.spotifyConnect, true)
 MusicCommands.speakerOnCommand.run()
 precondition(AppCore.shared.messages.last == String(localized: "Spotify Connect Speaker is already on."))
 MusicCommands.speakerOffCommand.run()
 precondition(!preferences.isOn(.spotifyConnect))
 MusicCommands.speakerOffCommand.run()
 precondition(AppCore.shared.messages.last == String(localized: "Spotify Connect Speaker is already off."))
 preferences.set(.musicLastPlayer, true)
 music.model.lastPlayer.setEnabled(false)
 precondition(!music.model.canResume)
 MusicCommands.resumeLastPlayer()
 precondition(source.commands.last == .play)
 music.model.reportCommandFailure()
 precondition(music.model.failure == .playbackFailed("fixture"), "playing track retains command rejection")
 MusicCommands.send(.pause)
 let before = AppCore.shared.appIndex.refreshes
 preferences.set(.musicNowPlaying, false)
 for _ in 0..<100 { await Task.yield() }
 precondition(AppCore.shared.appIndex.refreshes > before)
 precondition(commands.prefix(4).allSatisfy { !$0.isEnabled() })
 let musicRefresh = AppCore.shared.appIndex.refreshes
 preferences.set(.microphoneMute, false)
 for _ in 0..<100 { await Task.yield() }
 precondition(AppCore.shared.appIndex.refreshes > musicRefresh)
 preferences.set(.musicNowPlaying, true)
 music.model.setSystemSource(nil)
 music.model.lastPlayer.setEnabled(false)
 precondition(!music.model.canResume)
 let messages = AppCore.shared.messages.count
 MusicCommands.send(.togglePlayPause)
 precondition(AppCore.shared.messages.count == messages + 1)
 let adapter = SystemNowPlayingSource()
 music.model.setSystemSource(adapter)
 adapter.onCommandFailure = { [weak model = music.model] in model?.reportCommandFailure() }
 for _ in 0..<100 { await Task.yield() }
 precondition(music.model.failure == .unreadable(.system))
 precondition(AppCore.shared.messages.count == messages + 1, "background unreadable never shows a HUD")
 adapter.receiveCommand(sent: false)
 for _ in 0..<100 { await Task.yield() }
 precondition(music.model.failure == .playbackFailed(""))
 precondition(AppCore.shared.messages.count == messages + 2, "rejected command shows a HUD")
 MusicCommands.openCurrentPlayer()
 precondition(!AppCore.shared.messages.isEmpty)
 print("PASS: music and microphone commands, feature/island gating, speaker Settings consent, resume and failure HUDs")
 }
}
