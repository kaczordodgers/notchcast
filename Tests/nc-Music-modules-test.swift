// notchcast-sources: Tinycast/Features/Music/Model/*.swift
// notchcast-sources: Tinycast/Features/Music/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastCore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastKeyMonitor.swift
// notchcast-sources: Tinycast/Features/Microphone/Model/*.swift
// notchcast-sources: Tinycast/Features/Microphone/Service/*.swift
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
import Foundation

@MainActor
final class CountingModule: NotchcastModule {
    var starts = 0
    var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
}

@MainActor final class AppCore {}

@MainActor
final class NotchcastServices {
    let music = CountingModule()
    let lastPlayer = CountingModule()
    let appleMusic = CountingModule()
    let spotify = CountingModule()
    let microphone = CountingModule()
    let marks = CountingModule()
    let keys = Keys()

    init(core: AppCore, preferences: NotchcastPreferences) {}

    final class Keys {
        func run() {}
    }
}

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
        precondition(preferences.isOn(.inUseMarks))
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
        precondition(counters.values.allSatisfy { $0.starts == $0.stops })
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
        print("PASS: defaults, lifecycle, fork-local persistence, device name and all six production registrations")
    }

    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
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
            let grants: [NotchcastGrant] = [.musicLastPlayer, .musicBlockAppleMusic].contains(feature)
                ? [.accessibility] : []
            precondition(feature.requiredGrants == grants)
        }
        NotchcastCore.start(AppCore(), preferences: preferences)
        let services = NotchcastCore.services!
        let modules = [services.music, services.lastPlayer, services.appleMusic,
                       services.spotify, services.microphone, services.marks]
        precondition(modules.map(\.starts) == [1, 1, 1, 0, 1, 1])
        preferences.set(.spotifyConnect, true)
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
}
