@MainActor
final class LiveTimerModule: NotchcastModule {
    let store: LiveTimerStore

    init(store: LiveTimerStore = LiveTimerStore(active: false)) { self.store = store }

    func start() { store.resume() }
    func stop() { store.stop() }
}
