extension CopyPathModule: NotchcastRegistrant {
    static let shared = CopyPathModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.copyPath], module: shared)]
    }
}
