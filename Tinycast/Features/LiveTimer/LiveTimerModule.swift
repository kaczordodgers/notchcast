@MainActor
final class LiveTimerModule: NotchcastModule {
    let store = LiveTimerStore(active: false)

    func start() { store.resume() }
    func stop() { store.stop() }
}
