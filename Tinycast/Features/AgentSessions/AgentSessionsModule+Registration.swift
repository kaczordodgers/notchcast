extension AgentSessionsModule: NotchcastRegistrant {
    static let shared = AgentSessionsModule(availabilityChanged: { NotchcastHost.current.refreshNotchcastCommands() })

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.agentSessions], module: shared)]
    }
}
