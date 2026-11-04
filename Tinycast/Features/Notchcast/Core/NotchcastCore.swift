/// Modules and their entries live in `NotchcastCore+Modules.swift`.
@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?
    private static var monitor: MonitorModule?
    static var settingsBackupRestore: ForkSettingsBackupCoordinator?

    static func stopForTermination() async {
        settingsBackupRestore?.stop()
        settingsBackup.stop()
        battery.stop()
        await battery.waitUntilIdle()
        monitor?.stop()
        await monitor?.fans.waitUntilIdle()
    }

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        settingsBackupRestore = ForkSettingsBackupCoordinator(core: core)
        IslandController.shared.configurePages(core)
        let monitor = MonitorModule(preferences: .shared)
        self.monitor = monitor
        let controller = NotchcastModuleController(entries(core: core, monitor: monitor), preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
