extension ShelfModule: NotchcastRegistrant {
    static let shared = ShelfModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.shelfBetweenMacs], module: shared)]
    }
}
