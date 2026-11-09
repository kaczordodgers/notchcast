extension WaitingAlertsModule: NotchcastRegistrant {
    static let shared = WaitingAlertsModule(availabilityChanged: { AppCore.shared.appIndex.refreshNotchcastCommands() })

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.waitingAlerts], module: shared)]
    }
}
