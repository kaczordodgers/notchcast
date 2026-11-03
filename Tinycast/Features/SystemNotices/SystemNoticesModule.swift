import Observation

@MainActor @Observable
final class SystemNoticesModule: NotchcastModule {
    let manager: SystemNoticesManager
    let preferences = SystemNoticesPreferences()
    private(set) var latest: SystemNoticeEngine.Notice?

    init(manager: SystemNoticesManager = SystemNoticesManager()) { self.manager = manager }

    func start() {
        manager.onNotice = { [weak self] notice in
            guard let self, self.preferences.allows(notice) else { return }
            self.latest = notice
        }
        manager.start()
    }

    func stop() {
        manager.stop()
        manager.onNotice = nil
        latest = nil
    }
}
