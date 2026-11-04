@MainActor
enum NotchcastCore {
    static let eventTapHub = EventTapHub()
    static let lowDisk = LowDiskModule()
    static let systemNotices = SystemNoticesModule()
    static let systemLevels = SystemLevelsModule()
    static let brightness = DisplayBrightnessModule()
    static let timers = LiveTimerModule()
    static let weather = DayWeatherModule()
    static let markets = DayMarketsModule()
    static let quitProtection = QuitProtectionStore()
    static let pasteImage = PasteImageModule(hub: eventTapHub)
    static private(set) var pastePlain: PlainPasteModule?
    private static var controller: NotchcastModuleController?

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        IslandController.shared.configurePages(core)
        let pastePlain = PlainPasteModule(clipboard: core.clipboardManager)
        self.pastePlain = pastePlain
        let modules: [NotchcastModuleController.Entry] = [
            .init(requires: [.island], module: IslandController.shared),
            .init(requires: [.island, .lowDiskWarning], module: lowDisk),
            .init(requires: [.island, .systemNotices], module: systemNotices),
            .init(requires: [.island, .volumeLevels], module: systemLevels),
            .init(requires: [.displayBrightness], module: brightness),
            .init(requires: [.island, .liveTimers], module: timers),
            .init(requires: [.island, .dayWeather], module: weather),
            .init(requires: [.island, .dayMarkets], module: markets),
            .init(requires: [.pastePlain], module: pastePlain),
            .init(requires: [.pasteImage], module: pasteImage),
        ]
        let controller = NotchcastModuleController(modules, preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
