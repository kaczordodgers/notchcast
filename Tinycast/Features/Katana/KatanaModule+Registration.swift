extension KatanaModule: NotchcastRegistrant {
    static let shared = KatanaModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.katana], module: shared)]
    }
}
