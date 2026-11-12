extension SystemNoticesModule: NotchcastRegistrant {
    static let shared = SystemNoticesModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.island, .systemNotices], module: shared)]
    }
}
