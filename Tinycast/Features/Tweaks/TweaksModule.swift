import Foundation

@MainActor
final class TweaksModule: NotchcastModule {
    private(set) var running = false
    private let runner = SystemToolsProcessRunner()
    private let profileRunner: TweakProfileRunner

    init(profileRunner: TweakProfileRunner = .system) {
        self.profileRunner = profileRunner
    }

    func start() { running = true }
    func stop() { running = false }

    func requestProfile(keepingAI: Set<String>?, privacy: Set<String>) async throws -> URL {
        guard running, let identifier = Bundle.main.bundleIdentifier else {
            throw CocoaError(.userCancelled)
        }
        let data = try TweakProfile.data(bundleIdentifier: identifier, keepingAI: keepingAI, privacy: privacy)
        let folder = URL.cachesDirectory.appending(path: identifier).appending(path: "TweakProfiles")
        return try await profileRunner.requestApproval(data: data, folder: folder)
    }

    func apply(_ plan: MacSetupPlan) async -> TweakPlanRunner.Receipt? {
        guard running else { return nil }
        return await runner.apply(plan)
    }
}

extension TweakProfileRunner {
    static let system = Self { file in
        _ = try SystemToolsProcessRunner().run("/usr/bin/open", arguments: [file.path])
    }
}
