// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Launcher/GitHub/Model/*.swift
// notchcast-sources: Tinycast/Features/Launcher/GitHub/Service/*.swift
// notchcast-sources: Tinycast/Features/Launcher/GitHub/GitHubModule.swift
// notchcast-sources: Tinycast/Features/Launcher/ClearNotifications/Model/*.swift
// notchcast-sources: Tinycast/Features/Launcher/ClearNotifications/Service/*.swift
// notchcast-sources: Tinycast/Features/Launcher/ClearNotifications/ClearNotificationsModule.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
// notchcast-sources: Tinycast/Features/Launcher/Answers/Model/*.swift
// notchcast-sources: Tinycast/Features/Launcher/Answers/Service/*.swift
// notchcast-sources: Tinycast/Features/Launcher/Answers/LauncherAnswersModule.swift
// notchcast-sources: Tinycast/Features/Calculator/Model/*.swift
// notchcast-sources: Tinycast/Features/Launcher/CopyPath/Model/*.swift
// notchcast-sources: Tinycast/Features/Launcher/CopyPath/Service/*.swift
// notchcast-sources: Tinycast/Features/Launcher/CopyPath/CopyPathModule.swift
// notchcast-sources: Tinycast/Features/Launcher/SmallCommands/Model/*.swift
// notchcast-sources: Tinycast/Features/Launcher/SmallCommands/Service/*.swift
// notchcast-sources: Tinycast/Features/Launcher/SmallCommands/SmallCommandsModule.swift
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
        let rates = Data(#"[{"effectiveDate":"2026-11-03","rates":[{"code":"EUR","mid":4.25},{"code":"USD","mid":4}]}]"#.utf8)
        let answers = LauncherAnswersModule(provider: { NBPAnswerRateProvider { _ in (rates, 200) } })
        let copyPath = CopyPathModule()
        let small = SmallCommandsModule()
        let controller = NotchcastModuleController([
            .init(requires: [.githubSearch], module: github),
            .init(requires: [.clearNotifications], module: notifications),
            .init(requires: [.launcherAnswers], module: answers),
            .init(requires: [.copyPath], module: copyPath),
            .init(requires: [.smallCommands], module: small),
        ], preferences: preferences)
        controller.run()
        precondition(!github.isRunning && !notifications.isRunning)
        let features: [NotchcastFeature] = [.githubSearch, .clearNotifications,
            .launcherAnswers, .copyPath, .smallCommands]
        precondition(!answers.isRunning && !copyPath.isRunning && !small.isRunning)
        var reached = await launcherActionsReach(answers, small)
        precondition(reached == (false, false))
        for feature in features { preferences.set(feature, true) }
        for _ in 0..<20 { await Task.yield() }
        precondition(github.isRunning && notifications.isRunning)
        precondition(answers.isRunning && copyPath.isRunning && small.isRunning)
        reached = await launcherActionsReach(answers, small)
        precondition(reached == (true, true))
        let count = try await notifications.run(accessibilityGranted: true)
        precondition(count == 3)
        preferences.set(.island, false)
        for _ in 0..<20 { await Task.yield() }
        precondition(github.isRunning && notifications.isRunning)
        preferences.set(.githubSearch, false)
        preferences.set(.clearNotifications, false)
        for feature in features { preferences.set(feature, false) }
        for _ in 0..<20 { await Task.yield() }
        precondition(!github.isRunning && !notifications.isRunning)
        precondition(!answers.isRunning && !copyPath.isRunning && !small.isRunning)
        reached = await launcherActionsReach(answers, small)
        precondition(reached == (false, false))
        precondition(github.session.state == .idle)
        do {
            _ = try await notifications.run(accessibilityGranted: true)
            preconditionFailure("Disabled module ran")
        } catch ClearNotificationsModule.Failure.disabled { }
        print("PASS: all five launcher tool switches start and stop their modules")
    }

    /// Whether the answers and small-commands launcher actions work; copy path has its own harness.
    static func launcherActionsReach(_ answers: LauncherAnswersModule,
                                     _ small: SmallCommandsModule) async -> (Bool, Bool) {
        (await answers.answer(for: "100 usd to eur") != nil, (try? small.randomPassword()) != nil)
    }
}
