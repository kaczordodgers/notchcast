@MainActor
final class LiveTimerModule: NotchcastModule {
    let store: LiveTimerStore

    init(store: LiveTimerStore = LiveTimerStore(active: false)) { self.store = store }

    func start() { NotchcastHost.current.refreshNotchcastCommands(); store.resume() }
    func stop() { NotchcastHost.current.refreshNotchcastCommands(); store.stop() }
}
