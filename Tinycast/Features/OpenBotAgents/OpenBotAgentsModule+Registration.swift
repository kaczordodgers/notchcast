extension OpenBotAgentsModule: NotchcastRegistrant {
    static let shared = OpenBotAgentsModule(
        availabilityChanged: { NotchcastHost.current.refreshNotchcastCommands() }, report: OpenBotAgentsModule.report)

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.openBotAgents], module: shared)]
    }
}
