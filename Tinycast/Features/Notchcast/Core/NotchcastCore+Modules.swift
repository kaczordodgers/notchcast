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
    static let agentSessions = AgentSessionsModule(availabilityChanged: { AppCore.shared.appIndex.refreshNotchcastCommands() })
    static let finderTools = FinderToolsCoordinator(hub: eventTapHub)
    static let finderCut = FinderToolsModule(coordinator: finderTools, feature: .finderCutPaste)
    static let finderRename = FinderToolsModule(coordinator: finderTools, feature: .finderRename)
    static let pasteImage = PasteImageModule(hub: eventTapHub)
    static private(set) var pastePlain: PlainPasteModule?
    static let linkQuickFixes = LinkQuickFixModule()
    static let lowDisk = LowDiskModule()
    static let systemNotices = SystemNoticesModule()
    static let systemLevels = SystemLevelsModule()
    static let brightness = DisplayBrightnessModule()
    static let levelKeys = SystemLevelKeysModule(hub: eventTapHub, levels: systemLevels, brightness: brightness)
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
    static let torrents = TorrentModule(session: TorrentAria2Session(stateDirectory: AppPaths.applicationSupport().appending(path: "Torrents")))
    static let archives = ArchiveModule(preferences: .shared)
    static let editor = EditorCoordinator(preferences: .shared, editorPreferences: EditorPreferences(defaults: UserDefaults(suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".editor")!))
    static let quickLook = QuickLookCoordinator(preferences: .shared)
    static let machineBackup = MachineBackupCoordinator(tooling: MachineBackupRunner(), preferences: .shared)

    static func entries(core: AppCore, monitor: MonitorModule) -> [NotchcastModuleController.Entry] {
        agents.configure(core)
        agentCLI.configure(index: agents.index)
        let pastePlain = PlainPasteModule(clipboard: core.clipboardManager)
        self.pastePlain = pastePlain
        pasteImage.configureFeedback(core)
        return [
            .init(requires: [.katana], module: katana),
            .init(requires: [.treadmillWalk], module: treadmillWalk),
            .init(requires: [.treadmillHistory], module: treadmillHistory),
            .init(requires: [.agentActions], module: agents),
            .init(requires: [.agentActions, .agentCLI], module: agentCLI),
            .init(requires: [.appearance], module: core.appearanceCoordinator),
            .init(requires: [.agentSessions], module: agentSessions),
            .init(requires: [.finderCutPaste], module: finderCut),
            .init(requires: [.finderRename], module: finderRename),
            .init(requires: [.pastePlain], module: pastePlain),
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
            .init(requires: [.torrents], module: torrents),
            .init(requires: [.archives], module: archives),
            .init(requires: [], requiresAny: [.markdownFiles, .plainTextFiles], module: editor),
            .init(requires: [.quickLookSpace], module: quickLook),
            .init(requires: [], requiresAny: [.backupRunNow, .backupBrowseRestore], module: machineBackup),
        ]
    }
}
