import Observation

@MainActor @Observable
final class SystemLevelsModule: NotchcastModule {
    let service: SystemLevelsService
    private(set) var latest: LevelNotice?

    init(service: SystemLevelsService = SystemLevelsService()) { self.service = service }

    func start() {
        service.onLevelChange = { [weak self] notice in
            self?.latest = notice
        }
        service.start()
    }

    func stop() {
        service.stop()
        service.onLevelChange = nil
        latest = nil
    }
}
