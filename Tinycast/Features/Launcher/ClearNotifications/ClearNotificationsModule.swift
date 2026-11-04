@MainActor
final class ClearNotificationsModule: NotchcastModule {
    enum Failure: Error { case disabled }
    private(set) var isRunning = false
    private let runner: ClearNotificationsRunner
    private var revision = 0
    var commandTask: Task<Void, Never>?

    init(runner: ClearNotificationsRunner = ClearNotificationsRunner()) { self.runner = runner }

    func start() { isRunning = true }
    func stop() {
        isRunning = false
        revision &+= 1
        commandTask?.cancel()
        commandTask = nil
    }

    func run(accessibilityGranted: Bool) async throws -> Int {
        guard isRunning else { throw Failure.disabled }
        let stamp = revision
        let count = try await runner.run(accessibilityGranted: accessibilityGranted)
        guard isRunning, revision == stamp else { throw Failure.disabled }
        return count
    }
}
