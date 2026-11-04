import Foundation

@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?
    private static var monitor: MonitorModule?
    static func stopForTermination() async {
        settingsBackup.stop()
        battery.stop()
        await battery.waitUntilIdle()
        monitor?.stop()
        await monitor?.fans.waitUntilIdle()
    }

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        appleAppsUndo.onFailure = { [weak core] in core?.showMessage($0.localizedDescription) }
        if !NotchcastPreferences.shared.isOn(.appleAppsTweaks) { appleAppsUndo.stop() }
        spacesOrder.onFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not update Spaces ordering."), tone: .danger)
        }
        spacesOrder.restoreIfDisabled()
        IslandController.shared.configurePages(core)
        systemTools.configure(core)
        for module in [tweaks, typingTweaks, finderTweaks, dockTweaks, appleAppsTweaks, iPhoneBackupTweaks] {
            module.configure(core)
        }
        let monitor = MonitorModule(preferences: .shared)
        self.monitor = monitor
        let controller = NotchcastModuleController(entries(core: core, monitor: monitor), preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
