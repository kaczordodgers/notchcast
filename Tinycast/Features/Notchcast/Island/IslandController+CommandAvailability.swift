extension IslandController {
    func setCommandAvailable(_ available: Bool) {
        guard commandsAvailable != available else { return }
        commandsAvailable = available
        NotchcastHost.current.refreshNotchcastCommands()
    }
}
