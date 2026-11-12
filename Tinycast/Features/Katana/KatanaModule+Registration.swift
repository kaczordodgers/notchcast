extension KatanaModule: NotchcastRegistrant {
    static let shared = KatanaModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.katana], module: shared)]
    }
}
