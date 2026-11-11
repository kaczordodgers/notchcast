extension AgentIslandModule: NotchcastRegistrant {
    static let shared = AgentIslandModule.live()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.agentIsland], module: shared)]
    }
}
