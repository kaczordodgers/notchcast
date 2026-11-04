@MainActor
final class SmallCommandsModule: NotchcastModule {
    enum Failure: Error { case disabled }
    private(set) var isRunning = false
    private(set) var shortener: ShortenLinkService?
    private(set) var airDrop: AirDropService?

    func start() {
        isRunning = true
        shortener = ShortenLinkService()
        airDrop = AirDropService()
    }

    func stop() {
        isRunning = false
        shortener = nil
        airDrop?.stop()
        airDrop = nil
    }

    func randomPassword() throws -> String {
        guard isRunning else { throw Failure.disabled }
        return try RandomPasswordService.make()
    }

    func noiseControl(processID: Int32) throws -> NoiseControlService {
        guard isRunning else { throw Failure.disabled }
        return NoiseControlService(processID: processID)
    }
}
