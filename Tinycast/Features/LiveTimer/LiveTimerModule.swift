@MainActor
final class LiveTimerModule: NotchcastModule {
    let store: LiveTimerStore

    init(store: LiveTimerStore = LiveTimerStore(active: false)) { self.store = store }

    func start() { AppCore.shared.appIndex.refreshNotchcastCommands(); store.resume() }
    func stop() { AppCore.shared.appIndex.refreshNotchcastCommands(); store.stop() }
}
