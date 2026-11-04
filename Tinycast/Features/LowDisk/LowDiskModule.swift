import Observation

@MainActor @Observable
final class LowDiskModule: NotchcastModule {
    let manager: LowDiskManager
    private(set) var latest: LowDiskEngine.Space?

    init(manager: LowDiskManager = LowDiskManager()) { self.manager = manager }

    func start() {
        AppCore.shared.appIndex.refreshNotchcastCommands()
        manager.onNotice = { [weak self] in self?.latest = $0 }
        manager.start()
    }

    func stop() {
        AppCore.shared.appIndex.refreshNotchcastCommands()
        manager.stop()
        manager.onNotice = nil
        latest = nil
    }
}
