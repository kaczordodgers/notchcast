/// Modules and their entries live in `NotchcastCore+Modules.swift`.
@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?
    static private(set) var services: NotchcastServices?
    private static var monitor: MonitorModule?

    static func stopForTermination() async {
        settingsBackup.stop()
        battery.stop()
        await battery.waitUntilIdle()
        monitor?.stop()
        await monitor?.fans.waitUntilIdle()
    }

    static func start(_ core: AppCore, preferences: NotchcastPreferences = .shared) {
        guard controller == nil else { return }
        IslandController.shared.configurePages(core)
        let services = NotchcastServices(core: core, preferences: preferences)
        self.services = services
        let monitor = MonitorModule(preferences: .shared)
        self.monitor = monitor
        let controller = NotchcastModuleController(entries(core: core, monitor: monitor) + services.moduleEntries, preferences: preferences)
        self.controller = controller
        controller.run()
        services.keys.run()
    }
}
