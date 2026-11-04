import Foundation

/// One line per module and per entry, so branches that add modules merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
extension NotchcastCore {
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

    static func entries(core: AppCore, monitor: MonitorModule) -> [NotchcastModuleController.Entry] {
        let pastePlain = PlainPasteModule(clipboard: core.clipboardManager)
        self.pastePlain = pastePlain
        pasteImage.configureFeedback(core)
        return [
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
            .init(requires: [.island, .islandLiveActivities, .eventReminder], module: EventReminderModule(store: core.calendarStore)),
        ]
    }
}
