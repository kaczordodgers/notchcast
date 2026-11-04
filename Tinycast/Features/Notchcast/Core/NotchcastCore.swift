@MainActor
enum NotchcastCore {
    static let linkQuickFixes = LinkQuickFixModule()
    static let lowDisk = LowDiskModule()
    static let systemNotices = SystemNoticesModule()
    static let systemLevels = SystemLevelsModule()
    static let brightness = DisplayBrightnessModule()
    static let levelKeys = SystemLevelKeysModule(hub: eventTapHub, levels: systemLevels, brightness: brightness)
    static let timers = LiveTimerModule()
    static let weather = DayWeatherModule()
    static let markets = DayMarketsModule()
    static let macLink = AIUsageLinkModule()
    static let aiUsage = AIUsageModule(channel: macLink.channel, post: remoteNotice)
    static let machRemote = MachRemoteModule()
    static let shelf = ShelfModule()
    static let backupStatus = BackupStatusModule(path: { NotchcastPreferences.shared.backupStatusPath }, post: remoteNotice)
    static let sendFiles = SendFilesModule(preferences: .shared, runner: MachSSHProcessRunner.run,
        post: remoteNotice, changed: { AppCore.shared.appIndex.refreshNotchcastCommands() })
    static let updateRemote = UpdateRemoteModule(preferences: .shared, runner: MachSSHProcessRunner.run,
        post: remoteNotice, changed: { AppCore.shared.appIndex.refreshNotchcastCommands() })

    static let linkHealth = LinkHealthModule(probe: { try await macLink.channel.probeHealth() }) { text in
        guard NotchcastPreferences.shared.isOn(.islandStatusMessages) else { return }
        IslandActivityCenter.shared.showMessage(text, tone: .neutral, dwell: Theme.Duration.messageHUD)
    }
    static let quitProtection = QuitProtectionStore()
    static let eventTapHub = EventTapHub()
    static let quitProtectionModule = QuitProtectionModule(store: quitProtection, hub: eventTapHub)
    private static var controller: NotchcastModuleController?
    private static var monitor: MonitorModule?
    static let battery = BatteryModule(preferences: .shared, runner: .live)

    static func stopForTermination() async {
        battery.stop()
        await battery.waitUntilIdle()
        monitor?.stop()
        await monitor?.fans.waitUntilIdle()
    }

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        macLink.listenerRoute = { request in
            if request.method == "shelf-item" {
                guard await NotchcastPreferences.shared.isOn(.machLink),
                      await NotchcastPreferences.shared.isOn(.shelfBetweenMacs) else {
                    throw MachLinkMessage.Failure.disconnected
                }
                return try await ShelfMachLinkTransport.response(to: request, module: shelf)
            }
            return nil
        }
        let shelfChannel = MachLinkShelfChannel(channel: macLink.channel) {
            macLink.isRunning && macLink.isPaired && (!linkHealth.isRunning || linkHealth.health.reachability != .down)
        }
        shelf.linkStatus = shelfChannel
        shelf.transport = shelfChannel
        IslandController.shared.configurePages(core)
        let monitor = MonitorModule(preferences: .shared)
        self.monitor = monitor
        let modules: [NotchcastModuleController.Entry] = [
            .init(requires: [.linkQuickFixes], module: linkQuickFixes),
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
            .init(requires: [.aiUsage], module: aiUsage),
            .init(requires: [.machLink], module: macLink),
            .init(requires: [.machRemote], module: machRemote),
            .init(requires: [.machRemote, .sendFiles], module: sendFiles),
            .init(requires: [.machRemote, .updateRemote], module: updateRemote),
            .init(requires: [.backupStatus], module: backupStatus),
            .init(requires: [.machLink, .linkHealth], module: linkHealth),
            .init(requires: [.machLink, .shelfBetweenMacs], module: shelf),
        ]
        let controller = NotchcastModuleController(modules, preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
