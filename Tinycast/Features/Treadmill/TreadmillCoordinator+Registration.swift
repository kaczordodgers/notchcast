extension TreadmillCoordinator: NotchcastRegistrant {
    static let shared = TreadmillCoordinator.live()

    static func register() -> [NotchcastModuleController.Entry] {
        [
            .init(requires: [.treadmillWalk], module: TreadmillModule(shared, capability: .walk)),
            .init(requires: [.treadmillHistory], module: TreadmillModule(shared, capability: .history)),
        ]
    }
}
