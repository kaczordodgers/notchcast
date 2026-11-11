extension CopyPathModule: NotchcastRegistrant {
    static let shared = CopyPathModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.copyPath], module: shared)]
    }
}
