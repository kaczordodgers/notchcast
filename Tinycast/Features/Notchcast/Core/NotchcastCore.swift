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
    private static var controller: NotchcastModuleController?
    static private(set) var services: NotchcastServices?

    static func start(_ core: AppCore, preferences: NotchcastPreferences = .shared) {
        guard controller == nil else { return }
        IslandController.shared.configurePages(core)
        let services = NotchcastServices(core: core, preferences: preferences)
        self.services = services
        let modules: [NotchcastModuleController.Entry] = [
            .init(requires: [.island], module: IslandController.shared),
            .init(requires: [.island, .lowDiskWarning], module: lowDisk),
            .init(requires: [.island, .systemNotices], module: systemNotices),
            .init(requires: [.island, .volumeLevels], module: systemLevels),
            .init(requires: [.displayBrightness], module: brightness),
            .init(requires: [.island, .liveTimers], module: timers),
            .init(requires: [.island, .dayWeather], module: weather),
            .init(requires: [.island, .dayMarkets], module: markets)
        ] + services.moduleEntries
        let controller = NotchcastModuleController(modules, preferences: preferences)
        self.controller = controller
        controller.run()
        services.keys.run()
    }
}
