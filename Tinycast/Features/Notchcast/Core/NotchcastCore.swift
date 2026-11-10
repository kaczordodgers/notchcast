import AppKit

/// Modules and their entries live in `NotchcastCore+Modules.swift`, after them `+Registrants.swift`.
@MainActor
enum NotchcastCore {
    static let grantStatuses = NotchcastGrantState()
    private static var controller: NotchcastModuleController?
    static private(set) var services: NotchcastServices?
    private static var monitor: MonitorModule?
    private static let archiveServices = ArchiveServices()

    static func setFanMode(_ mode: FanControl.Mode) { monitor?.fans.set(mode) }
    static var confirmMacUpdate: () async -> Bool = { false }
    /// Hub glue: the settings backup reads Screen Text's option without naming its folder.
    static var screenTextRemovesLineBreaks: Bool {
        get { ScreenTextModule.shared.removeLineBreaks }
        set { ScreenTextModule.shared.removeLineBreaks = newValue }
    }

    static func stopForTermination() async {
        tasksSync.stop()
        KatanaModule.shared.stop()
        cleaning.stop()
        appUpdates.stop()
        await macUpdate.stopForTermination()
        dictationTrigger?.stop()
        await TreadmillCoordinator.shared.stopForTermination()
        settingsBackup.stop()
        CaptureTrimmerModule.shared.stop()
        voiceAsk?.stop()
        RecordingModule.shared.stop()
        await RecordingModule.shared.waitUntilIdle()
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
        NotchcastHost.current = NotchcastHost(
            showMessage: { [weak core] in core?.showMessage($0, tone: $1) },
            refreshNotchcastCommands: { [weak core] in core?.appIndex.refreshNotchcastCommands() },
            finderSelection: { try await CopyPathSystemReader.read(.finderSelection) },
            browserAddresses: { try await CopyPathSystemReader.read(.browser(CopyPathTarget(processID: $0, bundleID: $1))) }
        )
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
        DictationFamily.shared.historySink = { raw, cleaned in
            dictationHistory.enqueue(raw: raw, cleaned: cleaned)
        }
        dictationHistory.setStageEnabled = { DictationFamily.shared.setHistory($0) }
        Task { await dictationHistory.maintain() }
        dictationCleanup.reportFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not save dictation cleanup settings.", table: "Notchcast"), tone: .danger)
        }
        dictationCleanup.load()
        let shelfChannel = MachLinkShelfChannel(channel: macLink.channel, module: shelf) {
            macLink.isRunning && macLink.isPaired && (!linkHealth.isRunning || linkHealth.health.reachability != .down)
        }
        shelf.linkStatus = shelfChannel
        shelf.transport = shelfChannel
        ScreenshotModule.shared.openInEditor = { try CaptureEditorCoordinator.shared.openCapture(url: $0, clipboard: $1) }
        agents.devicesReady = { KatanaModule.shared.configure(index: $0); TreadmillCoordinator.shared.configure(index: $0) }
        FleetPanelModule.shared.transport = FleetMachLinkTransport(channel: macLink.channel)
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
        monitor.registerRemoteFanRoute(on: macLink.channel)
        if !NotchcastPreferences.shared.isOn(.systemMonitor)
            || !NotchcastPreferences.shared.isOn(.fanControl) {
            monitor.fans.restore(preservingPreference: true, silently: true)
        }
        let modules = entries(core: core, monitor: monitor) + registrants.flatMap { $0.register(core) }
        let controller = NotchcastModuleController(modules + services.moduleEntries, preferences: preferences)
        self.controller = controller
        controller.run()
        services.keys.run()
        #if DEBUG
        NotchcastLiveDemo.runIfRequested(core)
        #endif
    }
}
