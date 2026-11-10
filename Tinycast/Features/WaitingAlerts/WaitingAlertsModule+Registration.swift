extension WaitingAlertsModule: NotchcastRegistrant {
    static let shared = WaitingAlertsModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.waitingAlerts], module: shared)]
    }
}
