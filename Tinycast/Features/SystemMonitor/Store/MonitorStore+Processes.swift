extension MonitorStore {
    func quitProcess(_ identity: ProcessReading.Identity, force: Bool = false,
                     service: MonitorProcessService = MonitorProcessService()) -> MonitorProcessService.Outcome {
        service.quit(identity, force: force)
    }
}
