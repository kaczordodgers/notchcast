@MainActor
final class SmallCommandsModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var shortener: ShortenLinkService?
    private(set) var airDrop: AirDropService?
    var commandTask: Task<Void, Never>?

    func start() {
        isRunning = true
        shortener = ShortenLinkService()
        airDrop = AirDropService()
    }

    func stop() {
        isRunning = false
        commandTask?.cancel()
        commandTask = nil
        shortener = nil
        airDrop?.stop()
        airDrop = nil
    }

    func randomPassword() throws -> String {
        guard isRunning else { throw SmallCommandsFailure.disabled }
        return try RandomPasswordService.make()
    }

    func noiseControl(processID: Int32) throws -> NoiseControlService {
        guard isRunning else { throw SmallCommandsFailure.disabled }
        return NoiseControlService(processID: processID)
    }
}
