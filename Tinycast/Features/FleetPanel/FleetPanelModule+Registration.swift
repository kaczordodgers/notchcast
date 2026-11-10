extension FleetPanelModule: NotchcastRegistrant {
    static let shared = FleetPanelModule(availabilityChanged: { NotchcastHost.current.refreshNotchcastCommands() })

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.fleetPanel], module: shared)]
    }
}
