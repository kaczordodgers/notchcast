/// One line per module and per entry, so branches that add modules merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
import Foundation

extension NotchcastCore {
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
    static let colorPicker = ColorPickerModule()
    static let screenshot = ScreenshotModule()
    static let torrents = TorrentModule(session: TorrentAria2Session(stateDirectory: AppPaths.applicationSupport().appending(path: "Torrents")))
    static let archives = ArchiveModule(preferences: .shared)
    static let editor = EditorCoordinator(preferences: .shared, editorPreferences: EditorPreferences(defaults: UserDefaults(suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".editor")!))
    static let quickLook = QuickLookCoordinator(preferences: .shared)
    static let machineBackup = MachineBackupCoordinator(tooling: MachineBackupRunner(), preferences: .shared)

    static func entries(core: AppCore, monitor: MonitorModule) -> [NotchcastModuleController.Entry] {
        let pastePlain = PlainPasteModule(clipboard: core.clipboardManager)
        self.pastePlain = pastePlain
        pasteImage.configureFeedback(core)
        return [
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
            .init(requires: [.colorPicker], module: colorPicker),
            .init(requires: [.screenshot], module: screenshot),
            .init(requires: [.torrents], module: torrents),
            .init(requires: [.archives], module: archives),
            .init(requires: [], requiresAny: [.markdownFiles, .plainTextFiles], module: editor),
            .init(requires: [.quickLookSpace], module: quickLook),
            .init(requires: [], requiresAny: [.backupRunNow, .backupBrowseRestore], module: machineBackup),
            .init(requires: [.island, .islandLiveActivities, .eventReminder], module: EventReminderModule(store: core.calendarStore)),
        ]
    }
}
