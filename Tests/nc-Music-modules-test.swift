// notchcast-sources: Tinycast/Features/Music/Model/*.swift
// notchcast-sources: Tinycast/Features/Music/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Music/MusicNowPlayingModule+Registration.swift
// notchcast-sources: Tinycast/Features/Microphone/MicrophoneMuteModule+Registration.swift
// notchcast-sources: Tinycast/Features/Microphone/Settings/MicrophoneFailure+Settings.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastKeyMonitor.swift
// notchcast-sources: Tinycast/Features/Microphone/Model/*.swift
// notchcast-sources: Tinycast/Features/Microphone/Service/*.swift
// notchcast-sources: Tinycast/Features/Microphone/InUseMarksModule.swift
// notchcast-sources: Tinycast/Features/Microphone/MicrophoneMuteModule.swift
// notchcast-sources: Tinycast/Features/HotKeys/Service/HotKeyCenter.swift
// notchcast-sources: Tinycast/Features/HotKeys/Service/KeyShortcut.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HyperKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/ModifierKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyBinding.swift
// notchcast-sources: Tinycast/Platform/ASCIIKeyboardLayout.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Input/EventTapSubscription.swift
import Foundation
import AppKit
import Observation

enum Paster { static let tinycastEventTag: Int64 = 0x54494E59 }

@MainActor private var trusted = false
@MainActor func AXIsProcessTrusted() -> Bool { trusted }

enum EventTapPolicy {
    static func mask(for type: CGEventType) -> CGEventMask { 1 << type.rawValue }
}

@MainActor @Observable
final class EventTapHub {
    struct Event {}
    enum Verdict { case pass, swallow }
    @ObservationIgnored var handler: (@Sendable (CGEventType, CGEvent) -> Verdict)?
    @ObservationIgnored var removals = 0
    var isTrusted = false
    func registerSynchronous(mask: CGEventMask,
                             handler: @escaping @Sendable (CGEventType, CGEvent) -> Verdict) -> UUID {
        precondition(mask & EventTapPolicy.mask(for: .keyDown) != 0)
        self.handler = handler
        return UUID()
    }
    func register(mask: CGEventMask, handler: @escaping @MainActor @Sendable (Event) -> Void) -> UUID { UUID() }
    func remove(_ id: UUID) { removals += 1; handler = nil }
}

@MainActor
final class CountingModule: NotchcastModule {
    var starts = 0
    var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
}

@MainActor final class AppCore {}
enum DialogTone { case success, danger }

@main
@MainActor
struct MusicModuleTests {
    static func main() async {
        let suite = "music-modules.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(!preferences.isOn(.spotifyConnect))
        precondition(preferences.isOn(.musicNowPlaying))
        precondition(preferences.isOn(.musicLastPlayer))
        precondition(preferences.isOn(.musicBlockAppleMusic))
        precondition(preferences.isOn(.microphoneMute))
        precondition(!preferences.isOn(.inUseMarks), "hidden switches read off")
        let counters = Dictionary(uniqueKeysWithValues: NotchcastFeature.allCases.map { ($0, CountingModule()) })
        let entries = NotchcastFeature.allCases.map { feature in
            NotchcastModuleController.Entry(requires: [feature] + feature.dependencies, module: counters[feature]!)
        }
        let controller = NotchcastModuleController(entries, preferences: preferences)
        controller.run()
        let speaker = counters[.spotifyConnect]!
        let resume = counters[.musicLastPlayer]!
        let blocker = counters[.musicBlockAppleMusic]!
        preferences.set(.spotifyConnect, true)
        await settle()
        precondition(speaker.starts == 1)
        preferences.set(.musicNowPlaying, false)
        await settle()
        precondition(speaker.stops == 1 && resume.stops == 1 && blocker.stops == 0)
        preferences.set(.spotifyConnect, false)
        preferences.set(.musicNowPlaying, true)
        await settle()
        precondition(speaker.starts == 1 && resume.starts == 2)
        preferences.set(.spotifyConnect, true)
        await settle()
        preferences.set(.island, false)
        await settle()
        precondition(counters.filter { $0.key.needsIsland }.values.allSatisfy { $0.starts == $0.stops })
        preferences.set(.island, true)
        await settle()
        precondition(speaker.starts == 3)
        let restored = NotchcastPreferences(suiteName: suite)
        precondition(restored.isOn(.spotifyConnect))
        preferences.engineDefaults.set("test-player", forKey: LastPlayer.key)
        let lastPlayer = LastPlayer(defaults: preferences.engineDefaults, canPlay: { _ in true })
        precondition(lastPlayer.bundleID == "test-player")
        let source = SoloistSource()
        let module = SpotifyConnectModule(source: source, defaults: preferences.engineDefaults)
        module.setDeviceName("  Studio Mac  ")
        precondition(module.deviceName == "Studio Mac")
        precondition(defaults.string(forKey: "spotify.deviceName") == "Studio Mac")
        module.setDeviceName(" \n ")
        precondition(module.deviceName == "Notchcast")
        await registration()
        await routing()
        await installedBuild()
        print("PASS: defaults, lifecycle, fork-local persistence, device name and all six production registrations")
    }

    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    static func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    static func registration() async {
        let suite = "music-registration.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let features: [NotchcastFeature] = [
            .musicNowPlaying, .musicLastPlayer, .musicBlockAppleMusic, .spotifyConnect, .microphoneMute, .inUseMarks
        ]
        for feature in features {
            precondition(!feature.title.isEmpty && !feature.subtitle.isEmpty)
            let grants: [NotchcastGrant] = [.musicLastPlayer, .musicBlockAppleMusic, .microphoneMute].contains(feature)
                ? [.accessibility] : []
            precondition(feature.requiredGrants == grants)
        }
        precondition(MusicNowPlayingModule.shared == nil && MicrophoneMuteModule.shared == nil)
        let registered = MusicNowPlayingModule.register(AppCore()) + MicrophoneMuteModule.register(AppCore())
        precondition(registered.count == 7 && registered.allSatisfy { $0.requiresAny.isEmpty })
        precondition(registered[0].module === MusicNowPlayingModule.shared)
        precondition(registered[1].module is MusicLastPlayerModule)
        precondition(registered[2].module === MusicBlockAppleMusicModule.shared)
        precondition(registered[3].module is MusicSharpCoversModule)
        precondition(registered[4].module === SpotifyConnectModule.shared)
        precondition(registered[5].module === MicrophoneMuteModule.shared)
        precondition(registered[6].module === InUseMarksModule.shared)
        precondition(registered[3].requires == [.island, .musicNowPlaying, .musicSharpCovers])
        let counted = registered.map { _ in CountingModule() }
        let controller = NotchcastModuleController(zip(registered, counted).map {
            .init(requires: $0.requires, module: $1)
        }, preferences: preferences)
        controller.run()
        let modules = [counted[0], counted[1], counted[2], counted[4], counted[5], counted[6]]
        precondition(modules.map(\.starts) == [1, 1, 1, 0, 1, 0])
        preferences.set(.spotifyConnect, true)
        preferences.set(.inUseMarks, true)
        await settle()
        precondition(modules.map(\.starts) == [1, 1, 1, 1, 1, 1])
        preferences.set(.musicNowPlaying, false)
        await settle()
        precondition(modules.map(\.stops) == [1, 1, 0, 1, 0, 0])
        preferences.set(.islandStatusMessages, false)
        await settle()
        precondition(modules.map(\.starts) == [1, 1, 1, 1, 1, 1])
        preferences.set(.musicNowPlaying, true)
        await settle()
        for (feature, module) in zip(features, modules) {
            let before = module.stops
            preferences.set(feature, false)
            await settle()
            precondition(module.stops == before + 1)
            preferences.set(feature, true)
            await settle()
        }
        preferences.set(.island, false)
        await settle()
        precondition(modules.allSatisfy { $0.starts == $0.stops })
    }

    static func routing() async {
        let suite = "routing.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        var installed = false
        var launch: (@MainActor (PlayerApps.Launch) -> Void)?
        var quits = 0
        let apps = PlayerApps(isInstalled: { _ in installed }, isRunning: { _ in false },
                              open: { _ in }, play: { _ in }, watchLaunches: { launch = $0; return [] },
                              quit: { _ in quits += 1; return true })
        let music = MusicNowPlayingModule(defaults: defaults, apps: apps)
        music.model.lastPlayer.setEnabled(true)
        let audio = RoutingAudio()
        let mute = MicrophoneMute(audio: audio, defaults: defaults)
        let microphone = MicrophoneMuteModule(model: mute, showMessage: { _ in }, showFailure: { _ in })
        let blocker = MusicLaunchBlocker(apps: apps, uptime: { 10 }, gestureAge: { 5 },
                                         openReplacement: { _ in Task {} })
        blocker.setEnabled(true)
        let hub = EventTapHub()
        let monitor = NotchcastKeyMonitor(music: music, blocker: blocker, microphone: microphone,
                                         preferences: preferences, hub: hub)
        monitor.run()
        precondition(mute.hotKeyStatus == AXError.apiDisabled.rawValue)
        for down in [true, false] {
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: (16 << 16) | ((down ? 0x0a : 0x0b) << 8), data2: -1)!.cgEvent!
            precondition(hub.handler!(event.type, event) == .pass, "no replacement passes media keys through")
            installed = true
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            await settle()
            precondition(hub.handler!(event.type, event) == .swallow, "installed replacement consumes media keys")
            installed = false
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
            await settle()
        }
        await settle()
        preferences.set(.spotifyConnect, true)
        await settle()
        let media = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
            data1: (16 << 16) | (0x0a << 8), data2: -1)!.cgEvent!
        music.soloist.receive(#"{"type":"auth_state","loggedIn":true,"isActive":true,"deviceName":"Fixture"}"#)
        await settle()
        precondition(hub.handler!(media.type, media) == .swallow, "login automatically refreshes routing")
        music.soloist.connect(port: 0)
        await settle()
        precondition(hub.handler!(media.type, media) == .pass, "disconnect automatically clears routing")
        music.model.setSystemSource(nil)
        music.model.setSoloistSource(nil)
        music.model.setEnabled(true)
        music.model.lastPlayer.setEnabled(true)
        precondition(hub.handler!(media.type, media) == .pass)
        installed = true
        monitor.run()
        await settle()
        precondition(music.model.failure == nil, "a passed key cannot become a replacement during dispatch")
        precondition(hub.handler!(media.type, media) == .swallow)
        installed = false
        monitor.run()
        await settle()
        precondition(music.model.failure == .noReplacement, "a swallowed key keeps its replacement decision")
        hub.isTrusted = true
        await waitUntil { mute.hotKeyStatus == nil }
        precondition(mute.hotKeyStatus == nil, "the hub's permission grant clears the F5 warning")
        launch?(.init(bundleID: LastPlayer.appleMusic, processID: 123))
        precondition(quits == 1, "hub media key arms Apple Music blocking")
        microphone.start()
        let f5 = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: 96, keyDown: true)!
        precondition(hub.handler!(.keyDown, f5) == .swallow)
        await waitUntil { mute.isMuted }
        precondition(mute.isMuted, "F5 toggles mute through hub")
        microphone.setMuted(false)
        f5.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        precondition(hub.handler!(.keyDown, f5) == .swallow)
        precondition(hub.handler!(.keyUp, f5) == .swallow)
        await settle()
        precondition(!mute.isMuted, "F5 repeat and release do not toggle")
        microphone.setMuted(true)
        precondition(mute.isMuted)
        microphone.stop()
        precondition(!mute.isMuted && audio.input.mute[0].value == 0, "stop restores microphone")
        preferences.set(.island, false)
        await settle()
        precondition(hub.handler == nil && hub.removals == 1 && mute.hotKeyStatus == nil)
        hub.isTrusted = false
        await settle()
        precondition(mute.hotKeyStatus == nil, "a monitor with mute off shows no F5 warning")
        var reads = 0
        let key = SoloistKey(read: { reads += 1; throw SoloistFailure.keyUnavailable },
                            write: { _ in }, presence: { true })
        precondition((try? key.isSaved) == true && reads == 0, "presence never reads secret")
        print("PASS: production media-key routing, mute shutdown, Keychain presence")
    }

    static func installedBuild() async {
        let key = SoloistKey(read: { nil }, write: { _ in })
        let builds = RoutingBuilds()
        let speaker = SoloistSpeaker(key: key, builds: builds, launcher: LiveSoloistLauncher(),
                                     processes: LiveSoloistProcessList())
        await speaker.refreshInstalledBuild()
        precondition(speaker.build == builds.build, "installed build is visible without a key")
    }
}

@MainActor
final class RoutingBuilds: SoloistBuildSource {
    let build = SoloistBuild(executable: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                             version: "fixture", built: Date())
    func installed(excluding: Set<URL>) async throws -> SoloistBuild? { build }
    func install() async throws -> SoloistBuild { build }
}

@MainActor
final class RoutingAudio: MicrophoneAudioAccess {
    var monitoringFailure: MicrophoneInput.Failure?
    var input = MicrophoneInput(id: 1, uid: "fixture", mute: [.init(element: 0, value: 0)], volume: [])
    func inputs() throws(MicrophoneInput.Failure) -> [MicrophoneInput] { [input] }
    func write(_ levels: [MicrophoneInput.Level], control: MicrophoneInput.Control,
               on input: MicrophoneInput) throws(MicrophoneInput.Failure) { self.input.mute = levels }
    func start(change: @escaping @MainActor () -> Void) {}
    func stop() {}
}
