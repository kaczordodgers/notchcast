extension AgentThreadsModule: NotchcastRegistrant {
    static let shared = AgentThreadsModule(availabilityChanged: { NotchcastHost.current.refreshNotchcastCommands() })

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.agentThreads], module: shared)]
    }
}
