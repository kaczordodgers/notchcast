/// Modules and their entries live in `NotchcastCore+Modules.swift`.
@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?
    static private(set) var services: NotchcastServices?
    private static var monitor: MonitorModule?

    static func stopForTermination() async {
        dictationTrigger?.stop()
        settingsBackup.stop()
        captureTrimmer.stop()
        voiceAsk?.stop()
        recording.stop()
        await recording.waitUntilIdle()
        await editor.flushForTermination()
        machineBackup.stop()
        await machineBackup.waitUntilIdle()
        battery.stop()
        await battery.waitUntilIdle()
        monitor?.stop()
        await monitor?.fans.waitUntilIdle()
    }

    static func start(_ core: AppCore, preferences: NotchcastPreferences = .shared) {
        guard controller == nil else { return }
        dictationHistory.onFailure = { [weak core] in
            core?.showMessage(String(localized: "Couldn’t update dictation history."), tone: .danger)
        }
        DictationCleanup.transcriptObserver = { raw, cleaned in
            dictationHistory.enqueue(raw: raw, cleaned: cleaned)
        }
        dictationHistory.setStageEnabled = { DictationCleanup.setHistoryEnabled($0) }
        Task { await dictationHistory.maintain() }
        dictationCleanup.reportFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not save dictation cleanup settings."), tone: .danger)
        }
        dictationCleanup.load()
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
