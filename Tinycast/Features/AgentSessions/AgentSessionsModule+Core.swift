extension NotchcastCore {
    static let agentSessions = AgentSessionsModule(availabilityChanged: {
        AppCore.shared.appIndex.refreshNotchcastCommands()
    })
}
