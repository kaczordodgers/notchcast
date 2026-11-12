extension BlockedDialogModule: NotchcastRegistrant {
    static private(set) var shared: BlockedDialogModule?

    static func register() -> [NotchcastModuleController.Entry] {
        guard let linkChannel else { return [] }
        let module = linked(to: linkChannel)
        shared = module
        return [.init(requires: [.machBlockedDialogAlert], module: module)]
    }
}
