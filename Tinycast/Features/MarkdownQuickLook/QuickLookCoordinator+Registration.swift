extension QuickLookCoordinator: NotchcastRegistrant {
    static let shared = QuickLookCoordinator(preferences: .shared)

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.quickLookSpace], module: shared)]
    }
}
