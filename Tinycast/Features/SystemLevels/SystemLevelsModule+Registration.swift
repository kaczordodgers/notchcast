extension SystemLevelsModule: NotchcastRegistrant {
    static let shared = SystemLevelsModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.island, .volumeLevels], module: shared)]
    }
}
