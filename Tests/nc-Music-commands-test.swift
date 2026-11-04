// notchcast-sources: Tinycast/Features/Music/Model/*.swift
// notchcast-sources: Tinycast/Features/Music/Service/*.swift
// notchcast-sources: Tinycast/Features/Music/Commands/*.swift
// notchcast-sources: Tinycast/Features/Microphone/Model/*.swift
// notchcast-sources: Tinycast/Features/Microphone/Service/*.swift
// notchcast-sources: Tinycast/Features/Microphone/MicrophoneMuteModule.swift
// notchcast-sources: Tinycast/Features/Microphone/Commands/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
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
 enum Tone { case danger }
 let appIndex = AppIndex()
 var messages: [String] = []
 func showMessage(_ message: String, tone: Tone) { messages.append(message) }
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
                   duration: 100, elapsed: 0, stamp: .now, isPlaying: true, origin: .system)
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
 let originalLast = preferences.isOn(.musicLastPlayer)
 let originalSpeaker = preferences.isOn(.spotifyConnect)
 defer {
 preferences.set(.musicNowPlaying, originalMusic)
 preferences.set(.microphoneMute, originalMic)
 preferences.set(.island, originalIsland)
 preferences.set(.musicLastPlayer, originalLast)
 preferences.set(.spotifyConnect, originalSpeaker)
 }
 preferences.set(.island, true)
 preferences.set(.musicNowPlaying, true)
 preferences.set(.microphoneMute, true)
 preferences.set(.musicLastPlayer, true)
 var opened: [String] = []
 var played: [String] = []
 let apps = PlayerApps(isInstalled: { $0 == LastPlayer.spotify }, isRunning: { _ in false },
 open: { opened.append($0) }, play: { played.append($0) }, watchLaunches: { _ in [] }, quit: { _ in true })
 let music = MusicNowPlayingModule(defaults: defaults, apps: apps)
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
 defer { music.stop(); microphone.stop(); NotchcastCore.services = nil }
 let commands = MusicCommands.launcherCommands
 func command(_ slug: String) -> NotchcastCommand {
 commands.first { $0.id == "command:nc-" + slug }!
 }
 let additions = ["resume-last-player", "spotify-connect-speaker-on", "spotify-connect-speaker-off",
                  "mute-microphone", "unmute-microphone"]
 precondition(Set(commands.map(\.id)).count == commands.count)
 precondition(additions.allSatisfy { command($0).isEnabled() })
 precondition(commands.allSatisfy { $0.isEnabled() })
 command("mute-microphone").run()
 command("mute-microphone").run()
 precondition(mute.isMuted)
 command("unmute-microphone").run()
 command("unmute-microphone").run()
 precondition(!mute.isMuted)
 let speakerRefresh = AppCore.shared.appIndex.refreshes
 preferences.set(.spotifyConnect, false)
 for _ in 0..<100 { await Task.yield() }
 command("spotify-connect-speaker-on").run()
 for _ in 0..<100 { await Task.yield() }
 precondition(preferences.isOn(.spotifyConnect))
 precondition(AppCore.shared.appIndex.refreshes > speakerRefresh)
 command("spotify-connect-speaker-off").run()
 precondition(!preferences.isOn(.spotifyConnect))
 let before = AppCore.shared.appIndex.refreshes
 preferences.set(.musicNowPlaying, false)
 for _ in 0..<100 { await Task.yield() }
 precondition(AppCore.shared.appIndex.refreshes > before)
 precondition(additions.prefix(3).allSatisfy { !command($0).isEnabled() })
 precondition(command("mute-microphone").isEnabled())
 let musicRefresh = AppCore.shared.appIndex.refreshes
 preferences.set(.microphoneMute, false)
 for _ in 0..<100 { await Task.yield() }
 precondition(AppCore.shared.appIndex.refreshes > musicRefresh)
 precondition(!command("mute-microphone").isEnabled())
 precondition(!command("unmute-microphone").isEnabled())
 preferences.set(.musicNowPlaying, true)
 music.model.setSystemSource(nil)
 music.model.lastPlayer.setEnabled(true)
 command("resume-last-player").run()
 try? await Task.sleep(for: .seconds(1.2))
 precondition(opened == [LastPlayer.spotify] && played == [LastPlayer.spotify])
 preferences.set(.musicLastPlayer, false)
 for _ in 0..<100 { await Task.yield() }
 precondition(!command("resume-last-player").isEnabled())
 MusicCommands.openCurrentPlayer()
 precondition(!AppCore.shared.messages.isEmpty)
 print("PASS: command IDs, switch gating, index refresh, resume routing, idempotent mute and unavailable player HUD")
 }
}
