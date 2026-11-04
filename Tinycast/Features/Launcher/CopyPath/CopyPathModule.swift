@MainActor
final class CopyPathModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var service: CopyPathService?
    var commandTask: Task<Void, Never>?
    private let makeService: () -> CopyPathService

    init(makeService: @escaping () -> CopyPathService = { CopyPathService() }) {
        self.makeService = makeService
    }

    func start() {
        isRunning = true
        service = makeService()
    }

    func stop() {
        isRunning = false
        commandTask?.cancel()
        commandTask = nil
        service = nil
    }
}
