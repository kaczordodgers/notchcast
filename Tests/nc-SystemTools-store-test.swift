// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-kit: root
// notchcast-sources: Tinycast/Features/SystemTools/Model/TouchIDPolicy.swift
// notchcast-sources: Tinycast/Features/SystemTools/UI/SystemToolsHelperPolicy.swift
// notchcast-sources: Tinycast/Features/SystemTools/UI/SystemToolsStore.swift
import Foundation

@main
struct SystemToolsStoreTests {
    @MainActor
    static func main() async throws {
        let suite = "app.notchcast.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        for feature in NotchcastFeature.allCases where feature.isSystemTweak {
            precondition(!preferences.isOn(feature))
            precondition(!feature.needsIsland)
        }
        precondition(preferences.isOn(.island))
        precondition(NotchcastFeature.systemToolsSettingsFeatures == [
            .startupItems, .notificationCleanup, .sudoTouchID, .aiFeaturesOff, .spotlightOff, .privacyChoices
        ])
        for feature in [NotchcastFeature.killProcess, .macSetup] {
            precondition(!feature.isWired)
        }
        precondition(NotchcastFeature.aiFeaturesOff.isWired && NotchcastFeature.privacyChoices.isWired)
        precondition(NotchcastFeature.notificationCleanup.requiredGrants == [.accessibility])
        var effects: [Bool] = []
        precondition(SystemToolsHelperPolicy.available(.sudoTouchID))
        precondition(SystemToolsHelperPolicy.available(.spotlightOff))
        let store = SystemToolsStore(preferences: preferences,
                                    available: { $0 != .sudoTouchID && $0 != .spotlightOff }) { _, enabled in
            effects.append(enabled)
        }
        try await store.set(.sudoTouchID, enabled: true)
        try await store.set(.spotlightOff, enabled: true)
        precondition(effects.isEmpty)
        precondition(!preferences.isOn(.sudoTouchID) && !preferences.isOn(.spotlightOff))
        try await store.set(.notificationCleanup, enabled: true)
        try await store.set(.notificationCleanup, enabled: false)
        precondition(effects == [true, false])
        precondition(!preferences.isOn(.notificationCleanup))
        enum Failure: Error { case refused }
        let failing = SystemToolsStore(preferences: preferences, available: { _ in true }) { _, _ in
            throw Failure.refused
        }
        do {
            try await failing.set(.macSetup, enabled: true)
            preconditionFailure("Expected failure")
        } catch Failure.refused {}
        precondition(!preferences.isOn(.macSetup))
        preferences.set(.killProcess, true)
        preferences.set(.startupItems, true)
        let reloaded = NotchcastPreferences(suiteName: suite)
        precondition(reloaded.isOn(.startupItems))
        precondition(!reloaded.isOn(.killProcess), "a hidden switch reloads off")
        print("System tools store: default-off, persistence, reversal callback and helper guards passed")
    }
}
