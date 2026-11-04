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
    static let typingTweaks = TweaksModule(key: "typingTweaksPlans")
    static let finderTweaks = TweaksModule(key: "finderTweaksPlans")
    static let dockTweaks = TweaksModule(key: "dockTweaksPlans")
    static let appleAppsTweaks = TweaksModule(key: "appleAppsTweaksPlans")
    static let iPhoneBackupTweaks = TweaksModule(key: "iPhoneBackupTweaksPlans")
    private static var controller: NotchcastModuleController?

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        IslandController.shared.configurePages(core)
        systemTools.configure(core)
        for module in [tweaks, typingTweaks, finderTweaks, dockTweaks, appleAppsTweaks, iPhoneBackupTweaks] {
            module.configure(core)
        }
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
            .init(requires: [.typingTweaks], module: typingTweaks),
            .init(requires: [.finderTweaks], module: finderTweaks),
            .init(requires: [.dockTweaks], module: dockTweaks),
            .init(requires: [.appleAppsTweaks], module: appleAppsTweaks),
            .init(requires: [.iPhoneBackupTweaks], module: iPhoneBackupTweaks),
        ]
        let controller = NotchcastModuleController(modules, preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
