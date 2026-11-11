import AppKit

/// Modules and their entries live in `NotchcastCore+Modules.swift`, after them `+Registrants.swift`.
@MainActor
enum NotchcastCore {
    static let grantStatuses = NotchcastGrantState()
    private static var controller: NotchcastModuleController?
    static private(set) var services: NotchcastServices?
    private static let archiveServices = ArchiveServices()

    static var confirmMacUpdate: () async -> Bool = { false }

    static func stopForTermination() async {
        tasksSync.stop()
        KatanaModule.shared.stop()
        cleaning.stop()
        appUpdates.stop()
        await macUpdate.stopForTermination()
        dictationTrigger?.stop()
        await TreadmillCoordinator.shared.stopForTermination()
        ForkSettingsBackupModule.shared.stop()
        CaptureTrimmerModule.shared.stop()
        voiceAsk?.stop()
        RecordingModule.shared.stop()
        await RecordingModule.shared.waitUntilIdle()
        await editor.flushForTermination()
        MachineBackupCoordinator.shared.stop()
        await MachineBackupCoordinator.shared.waitUntilIdle()
        BatteryModule.shared.stop()
        MonitorModule.shared.stop()
        await RootWait.drainForTermination {
            await BatteryModule.shared.waitUntilIdle()
            await MonitorModule.shared.fans.waitUntilIdle()
        }
        await DictationHistoryModule.shared.waitUntilIdle()
    }

    static func start(_ core: AppCore, preferences: NotchcastPreferences = .shared) {
        guard controller == nil else { return }
        NotchcastHost.current = NotchcastHost(
            showMessage: { [weak core] in core?.showMessage($0, tone: $1) },
            remoteResult: { remoteResult($0) },
            refreshNotchcastCommands: { [weak core] in core?.appIndex.refreshNotchcastCommands() },
            finderSelection: { try await CopyPathSystemReader.read(.finderSelection) },
            browserAddresses: { try await CopyPathSystemReader.read(.browser(CopyPathTarget(processID: $0, bundleID: $1))) }
        )
        NSApp.servicesProvider = archiveServices
        Task { await grantStatuses.refresh(NotchcastGrant.allCases) }
        BatteryModule.shared.repairAtLaunch()
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
        dictationCleanup.reportFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not save dictation cleanup settings.", table: "Notchcast"), tone: .danger)
        }
        dictationCleanup.load()
        let shelfChannel = MachLinkShelfChannel(channel: macLink.channel, module: ShelfModule.shared) {
            macLink.isRunning && macLink.isPaired && (!linkHealth.isRunning || linkHealth.health.reachability != .down)
        }
        ShelfModule.shared.linkStatus = shelfChannel
        ShelfModule.shared.transport = shelfChannel
        RemoteFanModule.linkChannel = macLink.channel
        RemoteScreenModule.linkChannel = macLink.channel
        BlockedDialogModule.linkChannel = macLink.channel
        LinkQuickFixModule.shared.state = {
            let reachability: LinkQuickFixModule.Reachability = switch linkHealth.health.reachability {
            case .up: .up
            case .down: .down
            case .unknown: .unknown
            }
            return (macLink.isRunning && macLink.isPaired, reachability)
        }
        ScreenshotModule.shared.openInEditor = { try CaptureEditorCoordinator.shared.openCapture(url: $0, clipboard: $1) }
        agents.devicesReady = { KatanaModule.shared.configure(index: $0); TreadmillCoordinator.shared.configure(index: $0) }
        FleetPanelModule.shared.transport = FleetMachLinkTransport(channel: macLink.channel)
        IslandController.shared.configurePages(core)
        systemTools.configure(core)
        let modules = entries(core: core) + registrants.flatMap { $0.register(core) }
        let services = NotchcastServices(core: core, preferences: preferences)
        self.services = services
        if let tasks = TodoModule.shared { tasksSync.connect(to: tasks) }
        MonitorModule.shared.registerRemoteFanRoute(on: macLink.channel)
        if !NotchcastPreferences.shared.isOn(.systemMonitor) || !NotchcastPreferences.shared.isOn(.fanControl) {
            MonitorModule.shared.fans.restore(preservingPreference: true, silently: true)
        }
        let controller = NotchcastModuleController(modules, preferences: preferences)
        self.controller = controller
        controller.run()
        services?.keys.run()
        #if DEBUG
        NotchcastLiveDemo.runIfRequested(core)
        #endif
    }
}
