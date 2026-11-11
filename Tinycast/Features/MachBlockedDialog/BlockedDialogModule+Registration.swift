extension BlockedDialogModule: NotchcastRegistrant {
    static private(set) var shared: BlockedDialogModule?

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        guard let linkChannel else { return [] }
        let module = linked(to: linkChannel)
        shared = module
        return [.init(requires: [.machLink, .island, .islandStatusMessages, .machBlockedDialogAlert], module: module)]
    }
}
