import Observation

@MainActor
@Observable
final class CleaningModeModule: NotchcastModule {
    private let engine: CleaningModeEngine
    private let granted: () -> Bool
    private var enabled = false
    var needsGrant = false
    var remaining: Double { engine.remaining }

    init(engine: CleaningModeEngine, granted: @escaping () -> Bool) {
        self.engine = engine
        self.granted = granted
    }

    func start() { enabled = true }
    func stop() { enabled = false; engine.stop(); needsGrant = false }

    func begin() {
        guard enabled else { return }
        needsGrant = !granted()
        guard !needsGrant else { return }
        engine.start()
    }
}
