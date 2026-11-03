@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?
    private static var monitor: MonitorModule?

    static func stopForTermination() async {
        monitor?.stop()
        await monitor?.fans.waitUntilIdle()
    }

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        IslandController.shared.configurePages(core)
        let monitor = MonitorModule(preferences: .shared)
        self.monitor = monitor
        let modules: [NotchcastModuleController.Entry] = [
            .init(requires: [.island], module: IslandController.shared),
            .init(requires: [.systemMonitor], module: monitor)
        ]
        let controller = NotchcastModuleController(modules, preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
