import Observation

@MainActor @Observable
final class SystemNoticesModule: NotchcastModule {
    let manager: SystemNoticesManager
    private(set) var latest: SystemNoticeEngine.Notice?

    init(manager: SystemNoticesManager = SystemNoticesManager()) { self.manager = manager }

    func start() {
        AppCore.shared.appIndex.refreshNotchcastCommands()
        manager.onNotice = { [weak self] notice in
            self?.latest = notice
        }
        manager.start()
    }

    func stop() {
        AppCore.shared.appIndex.refreshNotchcastCommands()
        manager.stop()
        manager.onNotice = nil
        latest = nil
    }
}
