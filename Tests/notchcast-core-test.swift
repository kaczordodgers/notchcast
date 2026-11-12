// notchcast-kit: core
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
import Foundation

@MainActor
final class TestModule: NotchcastModule {
    var starts = 0
    var stops = 0
    var terminations: [NotchcastTerminationPhase] = []
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func stopForTermination(_ phase: NotchcastTerminationPhase) async { await Task.yield(); terminations.append(phase) }
}

/// Lets the controller's re-armed observation run, which happens on the main actor's next turn.
@MainActor
func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

@main
@MainActor
struct NotchcastCoreTests {
    static func main() async {
        for feature: NotchcastFeature in [.showDesktop, .spacesOrder, .hideCommandM,
                                         .middleClick, .greenMaximize] {
            precondition(feature.settingsGroup == .system)
            precondition(!feature.needsIsland && !feature.isSystemFeature)
        }
        let suite = "notchcast-core-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let m0: Set = [
            "island", "islandExternalDisplays", "islandFullScreen", "islandHoverOpen",
            "islandStatusMessages", "islandLiveActivities", "launcherFromIsland"
        ]
        precondition(m0.isSubset(of: NotchcastFeature.allCases.map(\.rawValue)))
        for feature in NotchcastFeature.allCases where feature.isWired {
            precondition(!feature.title.isEmpty && !feature.subtitle.isEmpty, "Untitled switch: \(feature)")
        }
        precondition(m0.allSatisfy { preferences.isOn(NotchcastFeature(rawValue: $0)!) })
        precondition(!preferences.isOn(.systemMonitor) && !preferences.isOn(.fanControl))
        for feature: NotchcastFeature in [.audioPriority, .cleanJunk, .cleanHistory, .cleanAIData,
            .cleanDisk, .cleanPurge, .cleanOptimize, .cleanSystem, .cleaningMode, .appUpdates,
            .macUpdate, .startupItems, .notificationCleanup, .sudoTouchID,
            .aiFeaturesOff, .spotlightOff, .privacyChoices, .typingTweaks,
            .finderTweaks, .dockTweaks, .appleAppsTweaks, .iPhoneBackupTweaks, .buildStats] {
            precondition(!feature.defaultEnabled && !preferences.isOn(feature))
        }
        let l3: Set<NotchcastFeature> = [.lowDiskWarning, .systemNotices, .volumeLevels,
            .displayBrightness, .quitProtection, .liveTimers, .dayCalendar, .dayWeather, .dayMarkets]
        for feature in l3 {
            let needsAccessibility = [.volumeLevels, .displayBrightness, .quitProtection].contains(feature)
            precondition(feature.requiredGrants.contains(.accessibility) == needsAccessibility)
        }
        precondition(!preferences.isOn(.pastePlain) && preferences.isOn(.pasteImage))
        precondition(NotchcastFeature.finderCutPaste.settingsGroup == .finder)
        precondition(NotchcastFeature.finderRename.settingsGroup == .finder)
        precondition(!NotchcastFeature.finderCutPaste.needsIsland)
        precondition(NotchcastFeature.finderRename.requiredGrants == [.accessibility])
        precondition(NotchcastFeature.accessoryNotices.requiredGrants == [.bluetooth])
        precondition(NotchcastFeature.pastePlain.subtitle.contains("launcher"))
        precondition(NotchcastFeature.dayCalendar.needsIsland)
        precondition(!NotchcastFeature.displayBrightness.needsIsland)
        precondition(!NotchcastFeature.quitProtection.needsIsland)
        precondition(NotchcastFeature.allCases.allSatisfy { preferences.isOn($0) == ($0.defaultEnabled && $0.isWired) })
        precondition(l3.filter(\.isWired).allSatisfy { preferences.isOn($0) })
        precondition(![.aiUsage, .aiUsageOtherMac, .machLink].contains { preferences.isOn($0) })
        precondition(preferences.isOn(.torrents) && preferences.isOn(.torrentsUseIPhone))
        precondition(!preferences.isOn(.torrentsKeepSharing))
        precondition(NotchcastFeature.torrents.dependencies.isEmpty)
        for feature: NotchcastFeature in [.torrents, .torrentsUseIPhone, .torrentsKeepSharing] {
            precondition(!feature.needsIsland && !feature.isSystemFeature)
            precondition(feature.requiredGrants.isEmpty)
        }
        precondition(NotchcastFeature.torrentsUseIPhone.dependencies == [.torrents])
        precondition(NotchcastFeature.torrentsKeepSharing.dependencies == [.torrents])
        for feature in NotchcastFeature.allCases {
            preferences.set(feature, false)
            precondition(!NotchcastPreferences(suiteName: suite).isOn(feature))
            preferences.set(feature, true)
            precondition(NotchcastPreferences(suiteName: suite).isOn(feature) == feature.isWired)
        }
        let otherSuite = suite + ".other"
        defer { UserDefaults(suiteName: otherSuite)?.removePersistentDomain(forName: otherSuite) }
        preferences.set(.islandFullScreen, false)
        precondition(NotchcastPreferences(suiteName: otherSuite).isOn(.islandFullScreen))
        preferences.set(.islandFullScreen, true)

        let hover = TestModule()
        let ungated = TestModule()
        let battery = TestModule()
        preferences.set(.batteryChargeLimit, false)
        preferences.set(.keepAwake, false)
        let controller = NotchcastModuleController(
            [
                .init(requires: [.island, .islandHoverOpen], module: hover),
                .init(requires: [.launcherFromIsland], module: ungated),
                .init(requires: [], requiresAny: [.batteryChargeLimit, .keepAwake], module: battery)
            ], preferences: preferences)
        controller.run()
        precondition(battery.starts == 0)
        preferences.set(.keepAwake, true)
        await settle()
        precondition(battery.starts == 1)
        preferences.set(.batteryChargeLimit, true)
        preferences.set(.keepAwake, false)
        await settle()
        precondition(battery.starts == 1 && battery.stops == 0)
        preferences.set(.batteryChargeLimit, false)
        await settle()
        precondition(battery.stops == 1)
        precondition(hover.starts == 1 && hover.stops == 0 && ungated.starts == 1)

        preferences.set(.islandHoverOpen, false)
        await settle()
        precondition(hover.starts == 1 && hover.stops == 1)
        preferences.set(.islandHoverOpen, true)
        await settle()
        precondition(hover.starts == 2)

        // A module not listing `.island` keeps running when the island turns off.
        preferences.set(.island, false)
        await settle()
        precondition(hover.stops == 2 && ungated.stops == 0)
        // A switch no entry requires never restarts anything.
        preferences.set(.islandStatusMessages, false)
        await settle()
        precondition(hover.starts == 2 && hover.stops == 2 && ungated.starts == 1)
        preferences.set(.island, true)
        await settle()
        precondition(hover.starts == 3 && ungated.starts == 1 && ungated.stops == 0)

        preferences.set(.launcherFromIsland, false)
        await settle()
        precondition(ungated.stops == 1 && hover.stops == 2)
        let phases: [NotchcastTerminationPhase] = [.beforeMacUpdate, .beforeSettingsBackup, .beforeRootDrain, .afterRootDrain]
        for phase in phases { await controller.stopForTermination(phase) }
        precondition([hover, ungated, battery].allSatisfy { $0.terminations == phases })
        precondition(hover.stops == 2 && ungated.stops == 1 && battery.stops == 1)
        print("PASS: switches, persistence, Observation gating, awaited termination hooks for running and stopped modules")
    }
}
