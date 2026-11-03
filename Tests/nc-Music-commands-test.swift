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
// notchcast-sources: Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import AppKit

struct AppEntry { let id: String }
enum CommandID: String { case openCurrentPlayer = "command:open-current-player" }
enum AppIndex {
    struct Results {
        var entries: [AppEntry]
        var favoriteCount = 0
        var meetingCount = 0
        var suggestionCount = 0
        var matchCount = 0
    }
}

@MainActor final class AppCore {
    enum Tone { case danger }
    var messages: [String] = []
    func showMessage(_ message: String, tone: Tone) { messages.append(message) }
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
    static func main() async throws {
        let suite = "music-commands.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let core = AppCore()
        let apps = PlayerApps(isInstalled: { _ in false }, isRunning: { _ in false },
                              open: { _ in }, play: { _ in }, watchLaunches: { _ in [] }, quit: { _ in true })
        let music = MusicNowPlayingModule(defaults: defaults, apps: apps)
        let observer = MusicCommandFeedback(music: music, core: core)
        defer { withExtendedLifetime(observer) {} }
        let source = CommandSource()
        music.model.setSystemSource(source)
        music.model.setSoloistSource(nil)
        music.start()
        for _ in 0..<20 { await Task.yield() }
        let audio = CommandAudio()
        let mute = MicrophoneMute(audio: audio, defaults: defaults)
        var feedback = 0
        let microphone = MicrophoneMuteModule(model: mute, showMessage: { _ in feedback += 1 },
                                               showFailure: { _ in feedback += 1 })
        microphone.start()
        NotchcastCore.services = .init(music: music, microphone: microphone)
        defer { music.stop(); microphone.stop(); NotchcastCore.services = nil }
        let ids: [SystemAction.ID] = [.playPause, .nextTrack, .previousTrack, .toggleMicrophoneMute]
        let entries = ids.map { AppEntry(id: SystemActionCatalog.action(id: $0).entryID) }
            + [AppEntry(id: CommandID.openCurrentPlayer.rawValue), AppEntry(id: "unrelated")]
        let results = AppIndex.Results(entries: entries, favoriteCount: 2, matchCount: 6)
        precondition(MusicCommands.listed(results, preferences: preferences).entries.count == 6)
        for id in ids.prefix(3) { precondition(MusicCommands.run(id, core: core, preferences: preferences)) }
        precondition(source.commands == [.togglePlayPause, .next, .previous])
        precondition(MicrophoneCommands.run(.toggleMicrophoneMute, preferences: preferences))
        precondition(mute.isMuted && feedback == 1)
        preferences.set(.musicNowPlaying, false)
        let filtered = MusicCommands.listed(results, preferences: preferences)
        precondition(filtered.entries.count == 2 && filtered.favoriteCount == 0 && filtered.matchCount == 2)
        precondition(MusicCommands.run(.nextTrack, core: core, preferences: preferences))
        precondition(source.commands.count == 3)
        preferences.set(.microphoneMute, false)
        precondition(MicrophoneCommands.run(.toggleMicrophoneMute, preferences: preferences))
        precondition(mute.isMuted && feedback == 1)
        precondition(MusicCommands.listed(results, preferences: preferences).entries.map(\.id) == ["unrelated"])
        preferences.set(.musicNowPlaying, true)
        preferences.set(.microphoneMute, true)
        preferences.set(.island, false)
        precondition(MusicCommands.listed(results, preferences: preferences).entries.count == 1)
        preferences.set(.island, true)
        music.model.setSystemSource(nil)
        precondition(MusicCommands.run(.nextTrack, core: core, preferences: preferences))
        precondition(core.messages.count == 1)
        await music.model.openReplacement(startingPlayback: false).value
        for _ in 0..<20 { await Task.yield() }
        precondition(core.messages.count == 2, "asynchronous engine failures reach the HUD")
        precondition(!MusicCommands.run(.lockScreen, core: core, preferences: preferences))
        precondition(!MicrophoneCommands.run(.lockScreen, preferences: preferences))
        let command = try String(contentsOfFile: "Tinycast/Features/Launcher/Model/CommandID.swift", encoding: .utf8)
        precondition(command.contains("case openCurrentPlayer = \"command:open-current-player\""))
        let routing = try String(contentsOfFile: "Tinycast/Features/SystemActions/UI/SystemActionCoordinator.swift",
                                 encoding: .utf8)
        precondition(routing.contains("MusicCommands.run(action.id, core: core) || MicrophoneCommands.run(action.id)"))
        print("PASS: five command registrations, module routing, switch gating, result counts and failure feedback")
    }
}
