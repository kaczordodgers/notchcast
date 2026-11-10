extension LowDiskModule: NotchcastRegistrant {
    static let shared = LowDiskModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.island, .lowDiskWarning], module: shared)]
    }
}
