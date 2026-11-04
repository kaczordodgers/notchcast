import Foundation

@MainActor
final class LauncherAnswersModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var provider: NBPAnswerRateProvider?

    func start() {
        isRunning = true
        provider = NBPAnswerRateProvider()
    }

    func stop() {
        isRunning = false
        provider = nil
    }
}
