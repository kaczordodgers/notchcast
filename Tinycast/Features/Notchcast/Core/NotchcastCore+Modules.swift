/// One line per module and per entry, so branches that add modules merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
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
