extension SystemNoticesModule: NotchcastRegistrant {
    static let shared = SystemNoticesModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.island, .systemNotices], module: shared)]
    }
}
