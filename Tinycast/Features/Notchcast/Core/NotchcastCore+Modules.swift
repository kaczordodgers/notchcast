extension NotchcastCore {
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
    static let systemTools = SystemToolsModule()
    static let tweaks = TweaksModule()
    static let typingTweaks = TweaksModule(key: "typingTweaksPlans")
    static let finderTweaks = TweaksModule(key: "finderTweaksPlans")
    static let dockTweaks = TweaksModule(key: "dockTweaksPlans")
    static let appleAppsTweaks = TweaksModule(key: "appleAppsTweaksPlans")
    static let iPhoneBackupTweaks = TweaksModule(key: "iPhoneBackupTweaksPlans")
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
        [
            .init(requires: [], requiresAny: [.startupItems, .notificationCleanup, .sudoTouchID, .killProcess], module: systemTools),
            .init(requires: [], requiresAny: [.macSetup, .aiFeaturesOff, .spotlightOff, .privacyChoices], module: tweaks),
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
            .init(requires: [.typingTweaks], module: typingTweaks),
            .init(requires: [.finderTweaks], module: finderTweaks),
            .init(requires: [.dockTweaks], module: dockTweaks),
            .init(requires: [.appleAppsTweaks], module: appleAppsTweaks),
            .init(requires: [.iPhoneBackupTweaks], module: iPhoneBackupTweaks),
            .init(requires: [.settingsBackup], module: settingsBackup),
            .init(requires: [.island, .islandLiveActivities, .eventReminder], module: EventReminderModule(store: core.calendarStore)),
        ]
    }
}
