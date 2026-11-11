extension SystemLevelsModule: NotchcastRegistrant {
    static let shared = SystemLevelsModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.island, .volumeLevels], module: shared)]
    }
}
