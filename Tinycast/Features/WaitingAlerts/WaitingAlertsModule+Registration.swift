extension WaitingAlertsModule: NotchcastRegistrant {
    static let shared = WaitingAlertsModule(availabilityChanged: { NotchcastHost.current.refreshNotchcastCommands() })

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.waitingAlerts], module: shared)]
    }
}
