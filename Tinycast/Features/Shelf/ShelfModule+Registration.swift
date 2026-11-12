extension ShelfModule: NotchcastRegistrant {
    static let shared = ShelfModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.shelfBetweenMacs], module: shared)]
    }
}
