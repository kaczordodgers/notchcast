import Foundation

/// One line per module and per entry, so branches that add modules merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
import Foundation

extension NotchcastCore {
    static let agents = AgentBridgeModule()
    static let agentCLI = AgentCLIModule()
    static let systemTools = SystemToolsModule()
    static let cleaning = CleaningModeModule(engine: CleaningModeEngine(hub: eventTapHub), granted: { Permissions.isAccessibilityTrusted() })
    static let appUpdates = AppUpdatesModule.live()
    static let macUpdate = MacUpdateModule(service: MacUpdateService(runner: MacUpdateRunner(), appRoot: "/Applications", exists: { FileManager.default.isExecutableFile(atPath: $0) }, resolve: { URL(filePath: $0).resolvingSymlinksInPath().path }, locked: { MacUpdateLock.isHeld(at: "/opt/homebrew/var/homebrew/locks/update") }))
    static let clean = CleanModule()
    static let macLink = AIUsageLinkModule()
    static let tasksSync = TodoLinkCoordinator.live(channel: macLink.channel, preferences: .shared)
    static let github = GitHubModule()
    static let answers = LauncherAnswersModule()
    static let urlCleaner = URLCleanerModule(defaults: UserDefaults(suiteName: NotchcastIdentity.current.suiteName(suffix: ".urlCleaner")))
    static let mediaTools = MediaToolsModule()
    static let convertFiles = ConvertFilesModule()
    static let aiUsage = AIUsageModule(channel: macLink.channel, post: remoteNotice)
    static let backupStatus = BackupStatusModule(path: { NotchcastPreferences.shared.backupStatusPath }, post: remoteNotice)
    static let linkHealth = LinkHealthModule(probe: { try await macLink.channel.probeHealth() }, post: remoteNotice)
    static let pasteImage = PasteImageModule(hub: eventTapHub)
    static let accessoryNotices = AccessoryNoticesModule()
    static let brightness = DisplayBrightnessModule()
    static let timers = LiveTimerModule.shared
    static let weather = DayWeatherModule.shared
    static let markets = DayMarketsModule.shared
    static let quitProtection = QuitProtectionStore.shared
    static let eventTapHub = EventTapHub.shared
    static let showDesktop = ShowDesktopModule(hub: eventTapHub)
    static let hideCommandM = HideCommandMModule(hub: eventTapHub)
    static let middleClick = MiddleClickModule(hub: eventTapHub)
    static let greenMaximize = GreenMaximizeModule(hub: eventTapHub)
    static let spacesOrder = SpacesOrderModule()
    static let eventReminder = EventReminderModule.shared
    static private(set) var agentChatTools: AgentChatToolsModule?
    static let agentMCPServer = AgentMCPModule()
    static var dictationTrigger: DictationTriggerModule?
    static let dictationCleanup = DictationCleanupModule.shared
    static private(set) var voiceAsk: VoiceAskModule?
    private static var voiceAskInput: VoiceAskInput?
    static let editor = EditorCoordinator.shared
    static let machineBackup = MachineBackupCoordinator(tooling: MachineBackupRunner(), preferences: .shared)

    static func entries(core: AppCore) -> [NotchcastModuleController.Entry] {
        agents.configure(core)
        agentCLI.configure(index: agents.index)
        if agents.configured { agentMCPServer.configure(index: agents.index) }
        let binaryPath = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/notchcast").path
        let chatTools = AgentChatToolsModule(store: core.mcpSettings, binaryPath: binaryPath, isBinaryInstalled: { FileManager.default.isExecutableFile(atPath: binaryPath) }, onChange: { [weak core] in core?.mcpCoordinator.applyEnabled() })
        agentChatTools = chatTools
        let trigger = makeDictationTrigger(core)
        dictationTrigger = trigger
        let voiceRecording = VoiceAskRecording(core: core)
        let voiceAskModule = VoiceAskModule(defaults: NotchcastIdentity.current.defaults, begin: voiceRecording.begin, finish: voiceRecording.finish, cancel: voiceRecording.cancel, message: { [weak core] in core?.showMessage($0, tone: $1) })
        self.voiceAsk = voiceAskModule
        voiceAskModule.configure(transport: VoiceAskCLITransport.production())
        voiceAskInput = VoiceAskInput(hub: eventTapHub, module: voiceAskModule)
        let downloadServices = NotchcastDownloadServices(core: core)
        let levelNotices = SystemLevelIslandPresenter(center: .shared)
        pasteImage.configureFeedback(core)
        core.clipboardManager.pasteboardDidChange = { urlCleaner.clipboardDidChange(URLCleanerSystemPasteboard($0)) }
        return [
            .init(requires: [.agentActions], module: agents),
            .init(requires: [.agentCLI], module: agentCLI),
            .init(requires: [.appearance], module: core.appearanceCoordinator),
            .init(requires: [], requiresAny: [.startupItems, .notificationCleanup, .sudoTouchID], module: systemTools),
            .init(requires: [.cleaningMode], module: cleaning),
            .init(requires: [.appUpdates], module: appUpdates),
            .init(requires: [.macUpdate], module: macUpdate),
            .init(requires: [], requiresAny: CleanCoordinator.features, module: clean.configure(core)),
            .init(requires: [.audioPriority], module: AudioPriorityModule()),
            .init(requires: [.githubSearch], module: github),
            .init(requires: [.launcherAnswers], module: answers),
            .init(requires: [.aiUsage], module: aiUsage),
            .init(requires: [.machLink], module: macLink),
            .init(requires: [.tasksSync], module: tasksSync),
            .init(requires: [.urlCleaner], module: urlCleaner),
            .init(requires: [.convertFiles], module: convertFiles),
            .init(requires: [.mediaTools], module: mediaTools),
            .init(requires: [], module: NotchcastToolsCommands(core: core)),
            .init(requires: [.downloads], module: DownloadsModule(core: core, services: downloadServices)),
            .init(requires: [.distill], module: DistillModule(core: core, services: downloadServices)),
            .init(requires: [.backupStatus], module: backupStatus),
            .init(requires: [.linkHealth], module: linkHealth),
            .init(requires: [.pasteImage], module: pasteImage),
            .init(requires: [.island], module: IslandController.shared),
            .init(requires: [.showDesktop], module: showDesktop),
            .init(requires: [.hideCommandM], module: hideCommandM),
            .init(requires: [.middleClick], module: middleClick),
            .init(requires: [.greenMaximize], module: greenMaximize),
            .init(requires: [.spacesOrder], module: spacesOrder),
            .init(requires: [.island, .accessoryNotices], module: accessoryNotices),
            .init(requires: [.displayBrightness], module: brightness),
            .init(requires: [], module: SystemLevelKeysModule(hub: eventTapHub, levels: SystemLevelsModule.shared, brightness: brightness, present: { levelNotices.present($0) })),
            .init(requires: [.quitProtection], module: QuitProtectionModule(store: quitProtection, hub: eventTapHub)),
            .init(requires: [.island, .liveTimers], module: timers),
            .init(requires: [.island, .dayWeather], module: weather),
            .init(requires: [.island, .dayMarkets], module: markets),
            .init(requires: [.eventReminder], module: eventReminder),
            .init(requires: [.agentChatTools], module: chatTools),
            .init(requires: [.agentMCPServer], module: agentMCPServer),
            .init(requires: [.globeDictation], module: trigger),
            .init(requires: [.dictationEnglish], module: DictationEnglishModule(hub: eventTapHub, coordinator: core.dictationCoordinator)),
            .init(requires: [.dictationCleanup], module: dictationCleanup),
            .init(requires: [.voiceAsk], module: voiceAskModule),
            .init(requires: [], requiresAny: [.markdownFiles, .plainTextFiles], module: editor),
            .init(requires: [], requiresAny: [.backupRunNow, .backupBrowseRestore], module: machineBackup),
        ]
    }
}
