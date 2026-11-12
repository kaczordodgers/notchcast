extension AgentIslandModule: NotchcastRegistrant {
    static let shared = AgentIslandModule.live()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.agentIsland], module: shared)]
    }
}
