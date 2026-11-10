extension NotchcastCore {
    static func makeDictationTrigger(_ core: AppCore) -> DictationTriggerModule {
        let family = DictationFamily.shared
        family.bind(core.dictationCoordinator)
        let manager = DictationTriggerManager(hub: eventTapHub, isRecording: { family.isRecording }) { action in
            switch action {
            case .start: family.start(inEnglish: NotchcastPreferences.shared.isOn(.dictationEnglish))
            case .finish: family.finish()
            case .cancel: family.cancel()
            }
        }
        return DictationTriggerModule(
            available: { family.isAvailable },
            paused: { [weak core] in core?.hotKeys.recordingAction != nil },
            reserve: { [weak core] in core?.hotKeys.globeReserved = $0 },
            configure: { manager.setEnabled($0, isPaused: $1) },
            teardown: { manager.stop() })
    }
}
