@MainActor
final class DayMarketsModule: NotchcastModule {
    let store = DayMarketsStore()
    private var enabled = false
    private var visible = false

    func start() { enabled = true; updateVisibility() }
    func stop() { enabled = false; store.setVisible(false) }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        updateVisibility()
    }

    private func updateVisibility() { store.setVisible(enabled && visible) }
}
