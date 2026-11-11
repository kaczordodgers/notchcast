@MainActor
final class DayMarketsModule: NotchcastModule {
    let store = DayMarketsStore()
    private var enabled = false
    private var visible = false

    func start() { NotchcastHost.current.refreshNotchcastCommands(); enabled = true; updateVisibility() }
    func stop() { NotchcastHost.current.refreshNotchcastCommands(); enabled = false; store.setVisible(false) }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        updateVisibility()
    }

    private func updateVisibility() { store.setVisible(enabled && visible) }
}
