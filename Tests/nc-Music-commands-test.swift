// notchcast-sources: Tinycast/Features/Music/Model/*.swift
// notchcast-sources: Tinycast/Features/Music/Service/*.swift
// notchcast-sources: Tinycast/Features/Music/Commands/*.swift
// notchcast-sources: Tinycast/Features/Microphone/Model/*.swift
// notchcast-sources: Tinycast/Features/Microphone/Service/*.swift
// notchcast-sources: Tinycast/Features/Microphone/Commands/*.swift
// notchcast-sources: Tinycast/Features/Microphone/MicrophoneMuteModule.swift
// notchcast-kit: host
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-kit: core platform command
import AppKit

enum DialogTone { case danger, success }
@MainActor final class AppCore {
 static let shared = AppCore()
 enum Target { case section(Anchor) }
 enum Anchor { case notchcastSpotify }
 let settingsCoordinator = Settings()
 final class Settings {
     var opens = 0
     func showSettings(tab: SettingsTab, revealing: Target) { opens += 1 }
 }
}
extension MusicNowPlayingModule { static var shared: MusicNowPlayingModule? }
extension MicrophoneMuteModule { static var shared: MicrophoneMuteModule? }
extension SpotifyConnectModule { static var shared: SpotifyConnectModule? }
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
 static var shown: [String] = []
 static var refreshes = 0

 static func main() async {
 NotchcastHost.current.showMessage = { message, _ in shown.append(message) }
 NotchcastHost.current.refreshNotchcastCommands = { refreshes += 1 }
 do {
     for mode in [RepeatMode.off, .all, .one] {
         let encoded = try SoloistProtocol.encode(.repeat(mode), isPlaying: false)
         let object = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
         precondition(object?["command"] as? String == "set_repeat_" + mode.rawValue)
     }
     let encoded = try SoloistProtocol.encode(.shuffle(false), isPlaying: true)
     let object = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
     precondition(object?["shuffle"] as? Bool == false)
     let queued = try SoloistProtocol.addToQueue(uri: "spotify:track:fixture")
     precondition(queued.contains("add_to_queue"))
     let notification = try SoloistProtocol.parse(#"{"type":"queue_changed"}"#, now: .now)
     precondition(notification == .changed(queue: true))
     let queueChange = try SoloistProtocol.parse(
         #"{"type":"queue_changed","upcoming":[{"item":{"decorations":{"identity":{"name":"Next"}}}}]}"#, now: .now)
     precondition(queueChange == .queue([.init(title: "Next", artist: nil, uri: nil)]))
     let source = SoloistSource()
     source.receive("""
         {"type":"playback_state","status":"playing",
          "item":{"decorations":{"identity":{"name":"Fixture"}}},
          "options":{"shuffle":true,"repeat":"all"}}
         """)
     var track = try await source.read()
     precondition(track?.shuffle == true && track?.repeatMode == .all)
     source.receive(#"{"type":"options_changed","shuffle":false,"repeat":"one"}"#)
     track = try await source.read()
     precondition(track?.shuffle == false && track?.repeatMode == .one)
     source.receive(#"{"type":"options_changed","shuffle":"unknown","repeat":42}"#)
     track = try await source.read()
     precondition(track?.shuffle == false && track?.repeatMode == .one && source.failure == nil)
     source.receive(#"{"type":"options_changed","shuffle":true}"#)
     track = try await source.read()
     precondition(track?.shuffle == true && track?.repeatMode == .one)
     source.receive("""
         {"type":"queue_changed","upcoming":[{"item":{"uri":"fixture","decorations":{
         "identity":{"name":"Next"},"creators":[{"entity":{"decorations":{"identity":{"name":"Artist"}}}}]}}}]}
         """)
     precondition(source.queue == [.init(title: "Next", artist: "Artist", uri: "fixture")])
     let model = MusicModel(defaults: .standard)
     model.setSoloistSource(source)
     precondition(model.queue == nil)
     model.setEnabled(true)
     precondition(model.queue == source.queue)
     model.setEnabled(false)
     precondition(model.queue == nil)
     source.receive(#"{"type":"queue_changed","upcoming":null}"#)
     source.receive(#"{"type":"queue_changed","upcoming":[]}"#)
     precondition(source.queue == [] && source.failure == nil)
     let adapter = SystemNowPlayingSource()
     adapter.send(.shuffle(true))
     precondition(adapter.commandFailure == .unsupportedCommand)
     adapter.send(.repeat(.one))
     precondition(adapter.commandFailure == .unsupportedCommand)
 } catch { preconditionFailure(String(describing: error)) }
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
 precondition(source.queue == nil)
 music.model.setSystemSource(source)
 music.model.setSoloistSource(nil)
 music.start()
 for _ in 0..<100 { await Task.yield() }
 let mute = MicrophoneMute(audio: CommandAudio(), defaults: defaults)
 let microphone = MicrophoneMuteModule(model: mute, showMessage: { _ in }, showFailure: { _ in })
 microphone.start()
 var hasKey = false
 let key = SoloistKey(read: { hasKey ? "fixture" : nil }, write: { _ in }, presence: { hasKey })
 MusicNowPlayingModule.shared = music
 MicrophoneMuteModule.shared = microphone
 SpotifyConnectModule.shared = SpotifyConnectModule(source: music.soloist, defaults: defaults, key: key)
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
 defer {
     music.stop(); microphone.stop()
     MusicNowPlayingModule.shared = nil; MicrophoneMuteModule.shared = nil; SpotifyConnectModule.shared = nil
 }
 let commands = MusicCommands.launcherCommands
 precondition(commands.allSatisfy { $0.isEnabled() })
 for command: PlayerCommand in [.togglePlayPause, .next, .previous] { MusicCommands.send(command) }
 precondition(source.commands == [.togglePlayPause, .next, .previous])
 let savedSpeaker = preferences.isOn(.spotifyConnect)
 let savedResume = preferences.isOn(.musicLastPlayer)
 defer {
     preferences.set(.spotifyConnect, savedSpeaker)
     preferences.set(.musicLastPlayer, savedResume)
 }
 let speakerCommands = [MusicCommands.speakerOnCommand, MusicCommands.speakerOffCommand]
 func speakerListed() -> Bool {
     speakerCommands.allSatisfy { $0.isEnabled() && $0.feature.map(preferences.isEnabled) == true }
 }
 preferences.set(.spotifyConnect, false)
 precondition(speakerListed(), "both speaker commands stay listed while the speaker is off")
 let opens = AppCore.shared.settingsCoordinator.opens
 MusicCommands.speakerOnCommand.run()
 precondition(preferences.isOn(.spotifyConnect), "On without a key still turns the speaker on")
 precondition(AppCore.shared.settingsCoordinator.opens == opens + 1, "On without a key opens Settings")
 hasKey = true
 MusicCommands.speakerOnCommand.run()
 precondition(shown.last == String(localized: "Spotify Connect Speaker is already on."))
 MusicCommands.speakerOffCommand.run()
 precondition(!preferences.isOn(.spotifyConnect))
 precondition(shown.last == String(localized: "Spotify Connect Speaker is off."))
 precondition(speakerListed(), "Off keeps both speaker commands listed")
 MusicCommands.speakerOffCommand.run()
 precondition(shown.last == String(localized: "Spotify Connect Speaker is already off."))
 MusicCommands.speakerOnCommand.run()
 precondition(preferences.isOn(.spotifyConnect), "On with a key starts the speaker directly")
 precondition(AppCore.shared.settingsCoordinator.opens == opens + 1, "On with a key opens no Settings")
 precondition(shown.last == String(localized: "Starting…"))
 preferences.set(.musicLastPlayer, true)
 music.model.lastPlayer.setEnabled(false)
 precondition(!music.model.canResume)
 MusicCommands.resumeLastPlayer()
 precondition(source.commands.last == .play)
 music.model.reportCommandFailure()
 precondition(music.model.failure == .playbackFailed("fixture"), "playing track retains command rejection")
 MusicCommands.send(.pause)
 let before = refreshes
 preferences.set(.musicNowPlaying, false)
 for _ in 0..<100 { await Task.yield() }
 precondition(refreshes > before)
 precondition(commands.prefix(4).allSatisfy { !$0.isEnabled() })
 let musicRefresh = refreshes
 preferences.set(.microphoneMute, false)
 for _ in 0..<100 { await Task.yield() }
 precondition(refreshes > musicRefresh)
 preferences.set(.musicNowPlaying, true)
 music.model.setSystemSource(nil)
 music.model.lastPlayer.setEnabled(false)
 precondition(!music.model.canResume)
 let messages = shown.count
 MusicCommands.send(.togglePlayPause)
 precondition(shown.count == messages + 1)
 let adapter = SystemNowPlayingSource()
 music.model.setSystemSource(adapter)
 adapter.onCommandFailure = { [weak model = music.model] in model?.reportCommandFailure() }
 for _ in 0..<100 { await Task.yield() }
 precondition(music.model.failure == .unreadable(.system))
 precondition(shown.count == messages + 1, "background unreadable never shows a HUD")
 adapter.receiveCommand(sent: false)
 for _ in 0..<100 { await Task.yield() }
 precondition(music.model.failure == .playbackFailed(""))
 precondition(shown.count == messages + 2, "rejected command shows a HUD")
 MusicCommands.openCurrentPlayer()
 precondition(shown.count == messages + 3, "no player to open reports it")
 precondition(shown.last == String(localized: "The current player is unavailable.", table: "Notchcast"))
 print("PASS: music and microphone commands, feature/island gating, speaker Settings consent, resume and failure HUDs")
 }
}
