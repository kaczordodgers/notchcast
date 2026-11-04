import Foundation

@MainActor
enum NotchcastCore {
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
    static let quitProtectionModule = QuitProtectionModule(store: quitProtection, hub: eventTapHub)
    private static var controller: NotchcastModuleController?
    private static var monitor: MonitorModule?
    static let battery = BatteryModule(preferences: .shared, runner: .live)
    static let cleaning = CleaningModeModule(engine: CleaningModeEngine(hub: eventTapHub),
                                             granted: { Permissions.isAccessibilityTrusted() })
    static let appUpdates = AppUpdatesModule.live()
    static let macUpdate = MacUpdateModule(service: MacUpdateService(
        runner: MacUpdateRunner(), home: NSHomeDirectory(), appRoot: "/Applications",
        exists: { FileManager.default.isExecutableFile(atPath: $0) },
        resolve: { URL(filePath: $0).resolvingSymlinksInPath().path }, locked: {
            MacUpdateLock.isHeld(at: "/opt/homebrew/var/homebrew/locks/update")
        }))
    static var confirmMacUpdate: () async -> Bool = { false }

    static func stopForTermination() async {
        cleaning.stop()
        appUpdates.stop()
        macUpdate.stop()
        await macUpdate.waitUntilIdle()
        battery.stop()
        await battery.waitUntilIdle()
        monitor?.stop()
        await monitor?.fans.waitUntilIdle()
    }

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        confirmMacUpdate = { [weak core] in
            guard let core else { return false }
            return await core.confirm(title: String(localized: "Update this Mac"),
                message: String(localized: """
                    Update Homebrew, upgrade packages, update Claude and Codex, then upgrade App Store apps. \
                    Updated Homebrew apps have quarantine removed.
                    """),
                symbol: "arrow.triangle.2.circlepath", confirmTitle: String(localized: "Run"))
        }
        IslandController.shared.configurePages(core)
        let monitor = MonitorModule(preferences: .shared)
        self.monitor = monitor
        let modules: [NotchcastModuleController.Entry] = [
            .init(requires: [.cleaningMode], module: cleaning),
            .init(requires: [.appUpdates], module: appUpdates),
            .init(requires: [.macUpdate], module: macUpdate),
            .init(requires: [.island], module: IslandController.shared),
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
        ]
        let controller = NotchcastModuleController(modules, preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
