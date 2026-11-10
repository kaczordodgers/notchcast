extension QuickLookCoordinator: NotchcastRegistrant {
    static let shared = QuickLookCoordinator(preferences: .shared)

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.quickLookSpace], module: shared)]
    }
}
