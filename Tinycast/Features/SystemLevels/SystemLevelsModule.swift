import Observation

@MainActor @Observable
final class SystemLevelsModule: NotchcastModule {
    let service: SystemLevelsService
    let preferences = SystemLevelsPreferences()
    private(set) var latest: LevelNotice?

    init(service: SystemLevelsService = SystemLevelsService()) { self.service = service }

    func start() {
        service.onLevelChange = { [weak self] notice in
            guard let self, notice.kind != .microphone || self.preferences.microphone else { return }
            self.latest = notice
        }
        service.start()
    }

    func stop() {
        service.stop()
        service.onLevelChange = nil
        latest = nil
    }
}
