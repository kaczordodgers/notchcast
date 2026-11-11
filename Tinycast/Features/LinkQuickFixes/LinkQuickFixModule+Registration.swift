extension LinkQuickFixModule: NotchcastRegistrant {
    static let shared = LinkQuickFixModule().configure()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.linkQuickFixes], module: shared)]
    }
}
