/// Modules and their entries live in `NotchcastCore+Modules.swift`.
@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?
    private static var monitor: MonitorModule?

    static func setFanMode(_ mode: FanControl.Mode) { monitor?.fans.set(mode) }

    static func stopForTermination() async {
        settingsBackup.stop()
        battery.stop()
        await battery.waitUntilIdle()
        monitor?.stop()
        await monitor?.fans.waitUntilIdle()
    }

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        battery.repairAtLaunch()
        NotchcastPreferences.shared.commandAvailabilityChanged = { [weak core] in
            core?.appIndex.refreshNotchcastCommands()
        }
        spacesOrder.onFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not update Spaces ordering."), tone: .danger)
        }
        spacesOrder.restoreIfDisabled()
        IslandController.shared.configurePages(core)
        let monitor = MonitorModule(preferences: .shared, alertSink: { [weak core] in
            core?.showMessage($0, tone: .danger)
        }, fanFailure: { [weak core] in
            core?.showMessage(String(localized: "Could not change fan mode."), tone: .danger)
        })
        self.monitor = monitor
        if !NotchcastPreferences.shared.isOn(.systemMonitor)
            || !NotchcastPreferences.shared.isOn(.fanControl) {
            monitor.fans.restore(preservingPreference: true, silently: true)
        }
        let controller = NotchcastModuleController(entries(core: core, monitor: monitor), preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
