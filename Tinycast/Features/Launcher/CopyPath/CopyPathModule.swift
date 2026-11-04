@MainActor
final class CopyPathModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var service: CopyPathService?

    func start() {
        isRunning = true
        service = CopyPathService()
    }

    func stop() {
        isRunning = false
        service = nil
    }
}
