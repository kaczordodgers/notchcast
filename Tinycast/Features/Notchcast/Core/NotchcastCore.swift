import AppKit

/// Modules and their entries live in `NotchcastCore+Modules.swift`.
@MainActor
enum NotchcastCore {
    static let grantStatuses = NotchcastGrantState()
    private static var controller: NotchcastModuleController?
    static private(set) var services: NotchcastServices?
    private static var monitor: MonitorModule?
    private static let archiveServices = ArchiveServices()

    static func setFanMode(_ mode: FanControl.Mode) { monitor?.fans.set(mode) }
    static var confirmMacUpdate: () async -> Bool = { false }

    static func stopForTermination() async {
        tasksSync.stop()
        katana.stop()
        cleaning.stop()
        appUpdates.stop()
        await macUpdate.stopForTermination()
        dictationTrigger?.stop()
        await treadmill.stopForTermination()
        settingsBackup.stop()
        captureTrimmer.stop()
        voiceAsk?.stop()
        recording.stop()
        await recording.waitUntilIdle()
        await editor.flushForTermination()
        machineBackup.stop()
        await machineBackup.waitUntilIdle()
        battery.stop()
        monitor?.stop()
        await RootWait.drainForTermination {
            await battery.waitUntilIdle()
            await monitor?.fans.waitUntilIdle()
        }
    }

    static func start(_ core: AppCore, preferences: NotchcastPreferences = .shared) {
        guard controller == nil else { return }
        NSApp.servicesProvider = archiveServices
        ArchiveCompressionCommands.selection = { try await CopyPathSystemReader.read(.finderSelection).map { URL(filePath: $0) } }
        archives.queue.compressionFinished = { [weak core] job in core?.showMessage(job.failure?.message ?? job.stateTitle, tone: job.failure == nil ? .neutral : .danger) }
        Task { await grantStatuses.refresh(NotchcastGrant.allCases) }
        battery.repairAtLaunch()
        NotchcastPreferences.shared.commandAvailabilityChanged = { [weak core] in
            core?.appIndex.refreshNotchcastCommands()
            core?.hotKeys.syncNotchcastCommands()
        }
        confirmMacUpdate = { [weak core] in
            guard let core else { return false }
            return await core.confirm(title: String(localized: "Update this Mac", table: "Notchcast"),
                message: String(localized: """
                    Update Homebrew, upgrade packages, update Claude and Codex, then upgrade App Store apps. \
                    Updated Homebrew apps have quarantine removed.
                    """, table: "Notchcast"),
                symbol: "arrow.triangle.2.circlepath", confirmTitle: String(localized: "Run"))
        }
        spacesOrder.onFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not update Spaces ordering.", table: "Notchcast"), tone: .danger)
        }
        spacesOrder.restoreIfDisabled()
        dictationHistory.onFailure = { [weak core] in
            core?.showMessage(String(localized: "Couldn’t update dictation history.", table: "Notchcast"), tone: .danger)
        }
        DictationCleanup.transcriptObserver = { raw, cleaned in
            dictationHistory.enqueue(raw: raw, cleaned: cleaned)
        }
        dictationHistory.setStageEnabled = { DictationCleanup.setHistoryEnabled($0) }
        Task { await dictationHistory.maintain() }
        dictationCleanup.reportFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not save dictation cleanup settings.", table: "Notchcast"), tone: .danger)
        }
        dictationCleanup.load()
        macLink.listenerRoute = { request in
            if let response = try await tasksSync.peerResponse(to: request, via: macLink.channel.manager) { return response }
            if request.method == "agent-threads" { return try await FleetMachLinkTransport.response(to: request) }
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
        systemTools.configure(core)
        for module in [tweaks, typingTweaks, finderTweaks, dockTweaks, appleAppsTweaks, iPhoneBackupTweaks] {
            module.configure(core)
        }
        let services = NotchcastServices(core: core, preferences: preferences)
        self.services = services
        tasksSync.connect(to: services.tasks)
        let monitor = MonitorModule(preferences: .shared, alertSink: { [weak core] in
            core?.showMessage($0, tone: .danger)
        }, fanFailure: { [weak core] in
            core?.showMessage(String(localized: "Could not change fan mode.", table: "Notchcast"), tone: .danger)
        })
        self.monitor = monitor
        macLink.channel.manager.fanHandler = { [weak monitor] request in guard let monitor else { throw RemoteFanReport.Failure.unavailable }; return try await monitor.remoteFanReport(request) }
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
