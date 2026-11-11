extension FinderToolsCoordinator: NotchcastRegistrant {
    static let shared = FinderToolsCoordinator(hub: .shared)

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [
            .init(requires: [.finderCutPaste], module: FinderToolsModule(coordinator: shared, feature: .finderCutPaste)),
            .init(requires: [.finderRename], module: FinderToolsModule(coordinator: shared, feature: .finderRename)),
        ]
    }
}
