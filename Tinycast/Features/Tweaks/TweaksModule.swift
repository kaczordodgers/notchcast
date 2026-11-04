@MainActor
final class TweaksModule: NotchcastModule {
    private(set) var running = false
    private let runner = SystemToolsProcessRunner()

    func start() { running = true }
    func stop() { running = false }

    func apply(_ plan: MacSetupPlan) async -> TweakPlanRunner.Receipt? {
        guard running else { return nil }
        return await runner.apply(plan)
    }
}
