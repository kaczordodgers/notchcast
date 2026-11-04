import Foundation

/// Modules and their entries live in `NotchcastCore+Modules.swift`.
@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?
    static private(set) var services: NotchcastServices?
    private static var monitor: MonitorModule?

    static func setFanMode(_ mode: FanControl.Mode) { monitor?.fans.set(mode) }
    static var confirmMacUpdate: () async -> Bool = { false }

    static func stopForTermination() async {
        cleaning.stop()
        appUpdates.stop()
        await macUpdate.stopForTermination()
        settingsBackup.stop()
        battery.stop()
        await battery.waitUntilIdle()
        monitor?.stop()
        await monitor?.fans.waitUntilIdle()
    }

    static func start(_ core: AppCore, preferences: NotchcastPreferences = .shared) {
        guard controller == nil else { return }
        battery.repairAtLaunch()
        NotchcastPreferences.shared.commandAvailabilityChanged = { [weak core] in
            core?.appIndex.refreshNotchcastCommands()
        }
        confirmMacUpdate = { [weak core] in
            guard let core else { return false }
            return await core.confirm(title: String(localized: "Update this Mac"),
                message: String(localized: """
                    Update Homebrew, upgrade packages, update Claude and Codex, then upgrade App Store apps. \
                    Updated Homebrew apps have quarantine removed.
                    """),
                symbol: "arrow.triangle.2.circlepath", confirmTitle: String(localized: "Run"))
        }
        spacesOrder.onFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not update Spaces ordering."), tone: .danger)
        }
        spacesOrder.restoreIfDisabled()
        IslandController.shared.configurePages(core)
        systemTools.configure(core)
        for module in [tweaks, typingTweaks, finderTweaks, dockTweaks, appleAppsTweaks, iPhoneBackupTweaks] {
            module.configure(core)
        }
        let services = NotchcastServices(core: core, preferences: preferences)
        self.services = services
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
        let controller = NotchcastModuleController(entries(core: core, monitor: monitor) + services.moduleEntries, preferences: preferences)
        self.controller = controller
        controller.run()
        services.keys.run()
    }
}
