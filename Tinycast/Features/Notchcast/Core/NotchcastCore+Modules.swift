import Foundation

/// One line per module and per entry, so branches that add modules merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
import Foundation

extension NotchcastCore {
    static let katana = KatanaModule()
    static let treadmillWalk = TreadmillModule(treadmill, capability: .walk)
    static let treadmillHistory = TreadmillModule(treadmill, capability: .history)
    static let treadmill = TreadmillCoordinator.live()
    static let agents = AgentBridgeModule()
    static let agentCLI = AgentCLIModule()
    static let systemTools = SystemToolsModule()
    static let tweaks = TweaksModule()
    static let typingTweaks = TweaksModule(key: "typingTweaksPlans")
    static let finderTweaks = TweaksModule(key: "finderTweaksPlans")
    static let dockTweaks = TweaksModule(key: "dockTweaksPlans")
    static let appleAppsTweaks = TweaksModule(key: "appleAppsTweaksPlans")
    static let iPhoneBackupTweaks = TweaksModule(key: "iPhoneBackupTweaksPlans")
    static let cleaning = CleaningModeModule(engine: CleaningModeEngine(hub: eventTapHub), granted: { Permissions.isAccessibilityTrusted() })
    static let appUpdates = AppUpdatesModule.live()
    static let macUpdate = MacUpdateModule(service: MacUpdateService(runner: MacUpdateRunner(), home: NSHomeDirectory(), appRoot: "/Applications", exists: { FileManager.default.isExecutableFile(atPath: $0) }, resolve: { URL(filePath: $0).resolvingSymlinksInPath().path }, locked: { MacUpdateLock.isHeld(at: "/opt/homebrew/var/homebrew/locks/update") }))
    static let clean = CleanModule()
    static let macLink = AIUsageLinkModule()
    static let github = GitHubModule()
    static let clearNotifications = ClearNotificationsModule()
    static let answers = LauncherAnswersModule()
    static let copyPath = CopyPathModule()
    static let smallCommands = SmallCommandsModule()
    static let urlCleaner = URLCleanerModule(defaults: UserDefaults(suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast") + ".urlCleaner"))
    static let mediaTools = MediaToolsModule()
    static let convertFiles = ConvertFilesModule()
    static let remoteFans = RemoteFanModule(transport: MachLinkFanTransport(channel: macLink.channel))
    static let remoteScreen = RemoteScreenModule(channel: macLink.channel)
    static let blockedDialogs = BlockedDialogModule.linked(to: macLink.channel)
    static let aiUsage = AIUsageModule(channel: macLink.channel, post: remoteNotice)
    static let machRemote = MachRemoteModule()
    static let shelf = ShelfModule()
    static let backupStatus = BackupStatusModule(path: { NotchcastPreferences.shared.backupStatusPath }, post: remoteNotice)
    static let sendFiles = SendFilesModule(preferences: .shared, runner: MachSSHProcessRunner.run, post: remoteResult, changed: { AppCore.shared.appIndex.refreshNotchcastCommands() })
    static let updateRemote = UpdateRemoteModule(preferences: .shared, runner: MachSSHProcessRunner.run, post: remoteResult, changed: { AppCore.shared.appIndex.refreshNotchcastCommands() })
    static let linkHealth = LinkHealthModule(probe: { try await macLink.channel.probeHealth() }, post: remoteNotice)
    static let agentSessions = AgentSessionsModule(availabilityChanged: { AppCore.shared.appIndex.refreshNotchcastCommands() })
    static let finderTools = FinderToolsCoordinator(hub: eventTapHub)
    static let finderCut = FinderToolsModule(coordinator: finderTools, feature: .finderCutPaste)
    static let finderRename = FinderToolsModule(coordinator: finderTools, feature: .finderRename)
    static let pasteImage = PasteImageModule(hub: eventTapHub)
    static private(set) var pastePlain: PlainPasteModule?
    static let linkQuickFixes = LinkQuickFixModule().configure()
    static let lowDisk = LowDiskModule()
    static let systemNotices = SystemNoticesModule()
    static let systemLevels = SystemLevelsModule()
    static let brightness = DisplayBrightnessModule()
    static let levelNoticePresenter = SystemLevelIslandPresenter(center: .shared)
    static let levelKeys = SystemLevelKeysModule(hub: eventTapHub, levels: systemLevels, brightness: brightness, present: { levelNoticePresenter.present($0) })
    static let timers = LiveTimerModule()
    static let weather = DayWeatherModule()
    static let markets = DayMarketsModule()
    static let quitProtection = QuitProtectionStore()
    static let eventTapHub = EventTapHub()
    static let showDesktop = ShowDesktopModule(hub: eventTapHub)
    static let hideCommandM = HideCommandMModule(hub: eventTapHub)
    static let middleClick = MiddleClickModule(hub: eventTapHub)
    static let greenMaximize = GreenMaximizeModule(hub: eventTapHub)
    static let spacesOrder = SpacesOrderModule()
    static let quitProtectionModule = QuitProtectionModule(store: quitProtection, hub: eventTapHub)
    static let battery = BatteryModule(preferences: .shared, runner: .live)
    static let settingsBackup = ForkSettingsBackupModule()
    static let settingsBackupRestore = ForkSettingsBackupCoordinator()
    static let eventReminder = EventReminderModule(store: AppCore.shared.calendarStore)
    static let colorPicker = ColorPickerModule()
    static let screenshot = ScreenshotModule()
    static let screenText = ScreenTextModule()
    static private(set) var agentChatTools: AgentChatToolsModule?
    static let agentMCPServer = AgentMCPModule()
    static var dictationTrigger: DictationTriggerModule?
    static let scrollingCapture = ScrollingCaptureModule()
    static let torrents = TorrentModule(session: TorrentAria2Session(stateDirectory: AppPaths.applicationSupport().appending(path: "Torrents")))
    static let archives = ArchiveModule(preferences: .shared)
    static let dictationCleanup = DictationCleanupModule.live()
    static let captureTrimmer = CaptureTrimmerModule.live()
    static let captureEditor = CaptureEditorCoordinator()
    static let agentAnswer = AgentAnswerModule()
    static let recording = RecordingModule()
    static private(set) var voiceAsk: VoiceAskModule?
    private static var voiceAskInput: VoiceAskInput?
    static let dictationHistory = DictationHistoryModule(repository: .init(directory: AppPaths.applicationSupport().appendingPathComponent("DictationHistory"), now: Date.init))
    static let editor = EditorCoordinator(preferences: .shared, editorPreferences: EditorPreferences(defaults: UserDefaults(suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".editor")!))
    static let quickLook = QuickLookCoordinator(preferences: .shared)
    static let machineBackup = MachineBackupCoordinator(tooling: MachineBackupRunner(), preferences: .shared)

    static func entries(core: AppCore, monitor: MonitorModule) -> [NotchcastModuleController.Entry] {
        agents.configure(core)
        agentCLI.configure(index: agents.index)
        let binaryPath = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/notchcast").path
        let chatTools = AgentChatToolsModule(store: core.mcpSettings, binaryPath: binaryPath, isBinaryInstalled: { FileManager.default.isExecutableFile(atPath: binaryPath) }, onChange: { [weak core] in core?.mcpCoordinator.applyEnabled() })
        agentChatTools = chatTools
        let trigger = makeDictationTrigger(core)
        dictationTrigger = trigger
        let voiceRecording = VoiceAskRecording(core: core)
        let voiceAskModule = VoiceAskModule(defaults: UserDefaults(suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!, begin: voiceRecording.begin, finish: voiceRecording.finish, cancel: voiceRecording.cancel)
        self.voiceAsk = voiceAskModule
        voiceAskInput = VoiceAskInput(hub: eventTapHub, module: voiceAskModule)
        let plainPasteModule = PlainPasteModule(clipboard: core.clipboardManager)
        self.pastePlain = plainPasteModule
        let downloadServices = NotchcastDownloadServices(core: core)
        pasteImage.configureFeedback(core)
        core.clipboardManager.pasteboardDidChange = { urlCleaner.clipboardDidChange(URLCleanerSystemPasteboard($0)) }
        return [
            .init(requires: [.katana], module: katana),
            .init(requires: [.treadmillWalk], module: treadmillWalk),
            .init(requires: [.treadmillHistory], module: treadmillHistory),
            .init(requires: [.agentActions], module: agents),
            .init(requires: [.agentActions, .agentCLI], module: agentCLI),
            .init(requires: [.appearance], module: core.appearanceCoordinator),
            .init(requires: [], requiresAny: [.startupItems, .notificationCleanup, .sudoTouchID, .killProcess], module: systemTools),
            .init(requires: [], requiresAny: [.macSetup, .aiFeaturesOff, .spotlightOff, .privacyChoices], module: tweaks),
            .init(requires: [.typingTweaks], module: typingTweaks),
            .init(requires: [.finderTweaks], module: finderTweaks),
            .init(requires: [.dockTweaks], module: dockTweaks),
            .init(requires: [.appleAppsTweaks], module: appleAppsTweaks),
            .init(requires: [.iPhoneBackupTweaks], module: iPhoneBackupTweaks),
            .init(requires: [.cleaningMode], module: cleaning),
            .init(requires: [.appUpdates], module: appUpdates),
            .init(requires: [.macUpdate], module: macUpdate),
            .init(requires: [], requiresAny: CleanCoordinator.features, module: clean.configure(core)),
            .init(requires: [.audioPriority], module: AudioPriorityModule()),
            .init(requires: [.githubSearch], module: github),
            .init(requires: [.clearNotifications], module: clearNotifications),
            .init(requires: [.launcherAnswers], module: answers),
            .init(requires: [.copyPath], module: copyPath),
            .init(requires: [.smallCommands], module: smallCommands),
            .init(requires: [.aiUsage], module: aiUsage),
            .init(requires: [.machLink], module: macLink),
            .init(requires: [.urlCleaner], module: urlCleaner),
            .init(requires: [.convertFiles], module: convertFiles),
            .init(requires: [.mediaTools], module: mediaTools),
            .init(requires: [], module: NotchcastToolsCommands(core: core)),
            .init(requires: [.downloads], module: DownloadsModule(core: core, services: downloadServices)),
            .init(requires: [.distill], module: DistillModule(core: core, services: downloadServices)),
            .init(requires: [.machRemote], module: machRemote),
            .init(requires: [.machRemote, .sendFiles], module: sendFiles),
            .init(requires: [.machRemote, .updateRemote], module: updateRemote),
            .init(requires: [.backupStatus], module: backupStatus),
            .init(requires: [.machLink, .linkHealth], module: linkHealth),
            .init(requires: [.machLink, .shelfBetweenMacs], module: shelf),
            .init(requires: [.machLink, .machMBPFans], module: remoteFans),
            .init(requires: [.machLink, .remoteScreen], module: remoteScreen),
            .init(requires: [.machLink, .island, .islandStatusMessages, .machBlockedDialogAlert], module: blockedDialogs),
            .init(requires: [.agentSessions], module: agentSessions),
            .init(requires: [.finderCutPaste], module: finderCut),
            .init(requires: [.finderRename], module: finderRename),
            .init(requires: [.pastePlain], module: plainPasteModule),
            .init(requires: [.pasteImage], module: pasteImage),
            .init(requires: [.linkQuickFixes], module: linkQuickFixes),
            .init(requires: [.island], module: IslandController.shared),
            .init(requires: [.showDesktop], module: showDesktop),
            .init(requires: [.hideCommandM], module: hideCommandM),
            .init(requires: [.middleClick], module: middleClick),
            .init(requires: [.greenMaximize], module: greenMaximize),
            .init(requires: [.spacesOrder], module: spacesOrder),
            .init(requires: [.systemMonitor], module: monitor),
            .init(requires: [], requiresAny: [.batteryChargeLimit, .batterySailing, .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake], module: battery),
            .init(requires: [.island, .lowDiskWarning], module: lowDisk),
            .init(requires: [.island, .systemNotices], module: systemNotices),
            .init(requires: [.island, .volumeLevels], module: systemLevels),
            .init(requires: [.displayBrightness], module: brightness),
            .init(requires: [], module: levelKeys),
            .init(requires: [.quitProtection], module: quitProtectionModule),
            .init(requires: [.island, .liveTimers], module: timers),
            .init(requires: [.island, .dayWeather], module: weather),
            .init(requires: [.island, .dayMarkets], module: markets),
            .init(requires: [.settingsBackup], module: settingsBackup),
            .init(requires: [.island, .islandLiveActivities, .eventReminder], module: eventReminder),
            .init(requires: [.colorPicker], module: colorPicker),
            .init(requires: [.screenshot], module: screenshot),
            .init(requires: [.screenText], module: screenText),
            .init(requires: [.agentChatTools], module: chatTools),
            .init(requires: [.agentMCPServer], module: agentMCPServer),
            .init(requires: [.globeDictation], module: trigger),
            .init(requires: [.dictationEnglish], module: DictationEnglishModule(hub: eventTapHub, coordinator: core.dictationCoordinator)),
            .init(requires: [.scrollingCapture], module: scrollingCapture),
            .init(requires: [.torrents], module: torrents),
            .init(requires: [.archives], module: archives),
            .init(requires: [.dictationCleanup], module: dictationCleanup),
            .init(requires: [.captureTrimmer], module: captureTrimmer),
            .init(requires: [.captureEditor], module: captureEditor),
            .init(requires: [.agentAnswer], module: agentAnswer),
            .init(requires: [.recording], module: recording),
            .init(requires: [.voiceAsk], module: voiceAskModule),
            .init(requires: [.dictationHistory], module: dictationHistory),
            .init(requires: [], requiresAny: [.markdownFiles, .plainTextFiles], module: editor),
            .init(requires: [.quickLookSpace], module: quickLook),
            .init(requires: [], requiresAny: [.backupRunNow, .backupBrowseRestore], module: machineBackup),
        ]
    }
}
