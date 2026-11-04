@MainActor
enum NotchcastCore {
    static let t3Threads = T3ThreadsModule()
    static let agentIsland = AgentIslandModule()
    static let botHost = BotHostModule()
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
    private static var controller: NotchcastModuleController?
    private static var monitor: MonitorModule?
    static let battery = BatteryModule(preferences: .shared, runner: .live)
    static let settingsBackup = ForkSettingsBackupModule()

    static func stopForTermination() async {
        settingsBackup.stop()
        battery.stop()
        await battery.waitUntilIdle()
        monitor?.stop()
        await monitor?.fans.waitUntilIdle()
    }

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        spacesOrder.onFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not update Spaces ordering."), tone: .danger)
        }
        spacesOrder.restoreIfDisabled()
        IslandController.shared.configurePages(core)
        let monitor = MonitorModule(preferences: .shared)
        self.monitor = monitor
        configureBotHost()
        let wiring = AgentFleetWiring(threads: t3Threads, fleet: fleet, island: agentIsland,
            bots: botHost, preferences: .shared, settings: fleetSettings) {
                IslandActivityCenter.shared.showMessage($0, tone: .neutral, dwell: 5)
            }
        let modules: [NotchcastModuleController.Entry] = [
            .init(requires: [.island, .agentIsland], module: agentIsland),
            .init(requires: [.linkQuickFixes], module: linkQuickFixes),
            .init(requires: [.island], module: IslandController.shared),
            .init(requires: [.showDesktop], module: showDesktop),
            .init(requires: [.hideCommandM], module: hideCommandM),
            .init(requires: [.middleClick], module: middleClick),
            .init(requires: [.greenMaximize], module: greenMaximize),
            .init(requires: [.spacesOrder], module: spacesOrder),
            .init(requires: [.systemMonitor], module: monitor),
            .init(requires: [], requiresAny: [.batteryChargeLimit, .batterySailing,
                .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake], module: battery),
            .init(requires: [.island, .lowDiskWarning], module: lowDisk),
            .init(requires: [.island, .systemNotices], module: systemNotices),
            .init(requires: [.island, .volumeLevels], module: systemLevels),
            .init(requires: [.displayBrightness], module: brightness),
            .init(requires: [], module: levelKeys),
            .init(requires: [.quitProtection], module: quitProtectionModule),
            .init(requires: [.island, .liveTimers], module: timers),
            .init(requires: [.island, .dayWeather], module: weather),
            .init(requires: [.island, .dayMarkets], module: markets),
            .init(requires: [.t3Threads], module: t3Threads),
            .init(requires: [.fleetPanel], module: fleet),
            .init(requires: [.botHost], module: botHost),
            .init(requires: [], module: wiring),
            .init(requires: [], module: AgentFleetBotCommands(bots: botHost, preferences: .shared,
                refresh: { core.appIndex.refreshNotchcastCommands() },
                post: { IslandActivityCenter.shared.showMessage($0, tone: .neutral, dwell: 5) })),
            .init(requires: [.settingsBackup], module: settingsBackup),
            .init(requires: [.island, .islandLiveActivities, .eventReminder],
                  module: EventReminderModule(store: core.calendarStore)),
        ]
        let controller = NotchcastModuleController(modules, preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
