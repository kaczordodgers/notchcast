/// Modules and their entries live in `NotchcastCore+Modules.swift`.
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
        macLink.listenerRoute = { request in
            if request.method == "shelf-item" {
                guard await NotchcastPreferences.shared.isOn(.machLink),
                      await NotchcastPreferences.shared.isOn(.shelfBetweenMacs) else {
                    throw MachLinkMessage.Failure.disconnected
                }
                return try await ShelfMachLinkTransport.response(to: request, module: shelf)
            }
            return nil
        }
        let shelfChannel = MachLinkShelfChannel(channel: macLink.channel) {
            macLink.isRunning && macLink.isPaired && (!linkHealth.isRunning || linkHealth.health.reachability != .down)
        }
        shelf.linkStatus = shelfChannel
        shelf.transport = shelfChannel
        IslandController.shared.configurePages(core)
        let monitor = MonitorModule(preferences: .shared)
        self.monitor = monitor
        let controller = NotchcastModuleController(entries(core: core, monitor: monitor), preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
