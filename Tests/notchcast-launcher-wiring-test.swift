// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Launcher/GitHub/Model/*.swift
// notchcast-sources: Tinycast/Features/Launcher/GitHub/Service/*.swift
// notchcast-sources: Tinycast/Features/Launcher/GitHub/GitHubModule.swift
// notchcast-sources: Tinycast/Features/Launcher/ClearNotifications/Model/*.swift
// notchcast-sources: Tinycast/Features/Launcher/ClearNotifications/Service/*.swift
// notchcast-sources: Tinycast/Features/Launcher/ClearNotifications/ClearNotificationsModule.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
import Foundation

@main
@MainActor
struct LauncherWiringTests {
    static func main() async throws {
        let suite = "launcher-wiring-test.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let github = GitHubModule(service: GitHubService(fetch: { _ in
            preconditionFailure("Wiring must never fetch")
        }))
        let notifications = ClearNotificationsModule(runner: ClearNotificationsRunner(execute: { _ in "3" }))
        let controller = NotchcastModuleController([
            .init(requires: [.githubSearch], module: github),
            .init(requires: [.clearNotifications], module: notifications),
        ], preferences: preferences)
        controller.run()
        precondition(!github.isRunning && !notifications.isRunning)
        for feature in [NotchcastFeature.githubSearch, .clearNotifications] {
            precondition(!feature.needsIsland && !feature.defaultEnabled)
            preferences.set(feature, true)
        }
        for _ in 0..<20 { await Task.yield() }
        precondition(github.isRunning && notifications.isRunning)
        let count = try await notifications.run(accessibilityGranted: true)
        precondition(count == 3)
        preferences.set(.island, false)
        for _ in 0..<20 { await Task.yield() }
        precondition(github.isRunning && notifications.isRunning)
        preferences.set(.githubSearch, false)
        preferences.set(.clearNotifications, false)
        for _ in 0..<20 { await Task.yield() }
        precondition(!github.isRunning && !notifications.isRunning)
        precondition(github.session.state == .idle)
        do {
            _ = try await notifications.run(accessibilityGranted: true)
            preconditionFailure("Disabled module ran")
        } catch ClearNotificationsModule.Failure.disabled { }
        precondition(NotchcastFeature.clearNotifications.requiredGrants == [.accessibility])
        print("PASS: GitHub and notifications switches gate modules independently of island")
    }
}
