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
        IslandController.shared.configurePages(core)
        let monitor = MonitorModule(preferences: .shared)
        self.monitor = monitor
        let controller = NotchcastModuleController(entries(core: core, monitor: monitor), preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
