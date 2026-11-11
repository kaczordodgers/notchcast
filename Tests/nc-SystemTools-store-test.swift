// notchcast-kit: core root
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
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
        }
        precondition(preferences.isOn(.island))
        precondition(NotchcastFeature.systemToolsSettingsFeatures == [
            .startupItems, .notificationCleanup, .sudoTouchID, .aiFeaturesOff, .spotlightOff, .privacyChoices
        ])
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
            try await failing.set(.privacyChoices, enabled: true)
            preconditionFailure("Expected failure")
        } catch Failure.refused {}
        precondition(!preferences.isOn(.privacyChoices))
        preferences.set(.machineSetupProfile, true)
        preferences.set(.startupItems, true)
        let reloaded = NotchcastPreferences(suiteName: suite)
        precondition(reloaded.isOn(.startupItems))
        precondition(!reloaded.isOn(.machineSetupProfile), "a hidden switch reloads off")
        print("System tools store: default-off, persistence, reversal callback and helper guards passed")
    }
}
