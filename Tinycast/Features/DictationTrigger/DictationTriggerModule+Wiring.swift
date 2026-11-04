extension NotchcastCore {
    static func makeDictationTrigger(_ core: AppCore) -> DictationTriggerModule {
        let manager = DictationTriggerManager(
            hub: eventTapHub,
            isRecording: { [weak core] in core?.dictationCoordinator.triggerIsRecording == true }
        ) { [weak core] action in
            switch action {
            case .start:
                core?.dictationCoordinator.triggerStarted(inEnglish: NotchcastPreferences.shared.isOn(.dictationEnglish))
            case .finish: core?.dictationCoordinator.triggerFinished()
            case .cancel: core?.dictationCoordinator.cancel()
            }
        }
        return DictationTriggerModule(
            available: { [weak core] in core?.dictationCoordinator.isEnabled == true },
            paused: { [weak core] in core?.hotKeys.recordingAction != nil },
            reserve: { [weak core] in core?.hotKeys.globeReserved = $0 },
            configure: { manager.setEnabled($0, isPaused: $1) },
            teardown: { manager.stop() })
    }
}
