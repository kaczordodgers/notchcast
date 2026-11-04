@MainActor
final class DayWeatherModule: NotchcastModule {
    let store: DayWeatherStore
    private var enabled = false
    private var visible = false

    init(store: DayWeatherStore = DayWeatherStore()) { self.store = store }

    func start() { AppCore.shared.appIndex.refreshNotchcastCommands(); enabled = true; updateVisibility() }
    func stop() { AppCore.shared.appIndex.refreshNotchcastCommands(); enabled = false; store.stop() }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        updateVisibility()
    }

    private func updateVisibility() {
        if enabled && visible { store.start() } else { store.stop() }
    }
}
