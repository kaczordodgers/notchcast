extension LowDiskModule: NotchcastRegistrant {
    static let shared = LowDiskModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.lowDiskWarning], module: shared)]
    }
}
