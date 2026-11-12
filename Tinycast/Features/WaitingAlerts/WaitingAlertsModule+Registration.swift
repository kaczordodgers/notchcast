extension WaitingAlertsModule: NotchcastRegistrant {
    static let shared = WaitingAlertsModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.waitingAlerts], module: shared)]
    }
}
