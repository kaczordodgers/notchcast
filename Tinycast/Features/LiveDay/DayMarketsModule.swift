@MainActor
final class DayMarketsModule: NotchcastModule {
    let store = DayMarketsStore()
    private var enabled = false
    private var visible = false

    func start() { AppCore.shared.appIndex.refreshNotchcastCommands(); enabled = true; updateVisibility() }
    func stop() { AppCore.shared.appIndex.refreshNotchcastCommands(); enabled = false; store.setVisible(false) }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        updateVisibility()
    }

    private func updateVisibility() { store.setVisible(enabled && visible) }
}
