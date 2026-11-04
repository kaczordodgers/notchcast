@MainActor
enum NotchcastCore {
    static let lowDisk = LowDiskModule()
    static let systemNotices = SystemNoticesModule()
    static let systemLevels = SystemLevelsModule()
    static let brightness = DisplayBrightnessModule()
    static let timers = LiveTimerModule()
    static let weather = DayWeatherModule()
    static let markets = DayMarketsModule()
    static let quitProtection = QuitProtectionStore()
    static let systemTools = SystemToolsModule()
    static let tweaks = TweaksModule()
    private static var controller: NotchcastModuleController?

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        IslandController.shared.configurePages(core)
        systemTools.configure(core)
        let modules: [NotchcastModuleController.Entry] = [
            .init(anyOf: [.startupItems, .notificationCleanup, .sudoTouchID, .killProcess], module: systemTools),
            .init(anyOf: [.macSetup, .aiFeaturesOff, .spotlightOff, .privacyChoices], module: tweaks),
            .init(requires: [.island], module: IslandController.shared),
            .init(requires: [.island, .lowDiskWarning], module: lowDisk),
            .init(requires: [.island, .systemNotices], module: systemNotices),
            .init(requires: [.island, .volumeLevels], module: systemLevels),
            .init(requires: [.displayBrightness], module: brightness),
            .init(requires: [.island, .liveTimers], module: timers),
            .init(requires: [.island, .dayWeather], module: weather),
            .init(requires: [.island, .dayMarkets], module: markets),
        ]
        let controller = NotchcastModuleController(modules, preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
