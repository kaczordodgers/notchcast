@MainActor
enum NotchcastCore {
    static let lowDisk = LowDiskModule()
    static let systemNotices = SystemNoticesModule()
    static let systemLevels = SystemLevelsModule()
    static let brightness = DisplayBrightnessModule()
    static let timers = LiveTimerModule()
    static let weather = DayWeatherModule()
    static let markets = DayMarketsModule()
    static let macLink = AIUsageLinkModule()
    static let aiUsage = AIUsageModule(channel: macLink.channel)
    static let quitProtection = QuitProtectionStore()
    static let linkHealth = LinkHealthModule(probe: { try await macLink.channel.probeHealth() }) { notice in
        switch notice {
        case .lost: _ = IslandHUDRouter.show(String(localized: "Mac link lost."), tone: .danger)
        case .recovered: _ = IslandHUDRouter.show(String(localized: "Mac link restored."), tone: .success)
        }
    }
    private static var controller: NotchcastModuleController?

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        IslandController.shared.configurePages(core)
        let modules: [NotchcastModuleController.Entry] = [
            .init(requires: [.island], module: IslandController.shared),
            .init(requires: [.island, .lowDiskWarning], module: lowDisk),
            .init(requires: [.island, .systemNotices], module: systemNotices),
            .init(requires: [.island, .volumeLevels], module: systemLevels),
            .init(requires: [.displayBrightness], module: brightness),
            .init(requires: [.island, .liveTimers], module: timers),
            .init(requires: [.island, .dayWeather], module: weather),
            .init(requires: [.island, .dayMarkets], module: markets),
            .init(requires: [.aiUsage], module: aiUsage),
            .init(requires: [.machLink], module: macLink),
            .init(requires: [.machLink, .linkHealth], module: linkHealth),
        ]
        let controller = NotchcastModuleController(modules, preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
