import Observation

@MainActor @Observable
final class SystemNoticesModule: NotchcastModule {
    let manager: SystemNoticesManager
    private(set) var latest: SystemNoticeEngine.Notice?

    init(manager: SystemNoticesManager = SystemNoticesManager()) { self.manager = manager }

    func start() {
        manager.onNotice = { [weak self] notice in
            self?.latest = notice
            Self.postNotice(notice)
        }
        manager.start()
    }

    func stop() {
        manager.stop()
        manager.onNotice = nil
        latest = nil
    }
}
