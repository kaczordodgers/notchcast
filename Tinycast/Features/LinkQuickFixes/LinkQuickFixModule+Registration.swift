extension LinkQuickFixModule: NotchcastRegistrant {
    static let shared = LinkQuickFixModule().configure()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.linkQuickFixes], module: shared)]
    }
}
