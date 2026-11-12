import Observation

@MainActor @Observable
final class LowDiskModule: NotchcastModule {
    let manager: LowDiskManager
    private(set) var latest: LowDiskEngine.Space?

    init(manager: LowDiskManager = LowDiskManager()) { self.manager = manager }

    func start() {
        manager.onNotice = { [weak self] in
            self?.latest = $0
            Self.postNotice($0)
        }
        manager.start()
    }

    func stop() {
        manager.stop()
        manager.onNotice = nil
        latest = nil
    }
}
