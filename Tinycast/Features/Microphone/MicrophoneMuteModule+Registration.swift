extension MicrophoneMuteModule: NotchcastRegistrant {
    static private(set) var shared: MicrophoneMuteModule?

    static func register() -> [NotchcastModuleController.Entry] {
        let mute = MicrophoneMute(audio: CoreMicrophoneAudio(), defaults: NotchcastPreferences.shared.engineDefaults)
        let microphone = MicrophoneMuteModule(
            model: mute, showMessage: { NotchcastHost.current.showMessage($0, .success) },
            showFailure: { NotchcastHost.current.showMessage($0.message, .danger) })
        let marks = InUseMarksModule(model: InUseMarks(isMuted: { [weak mute] in mute?.isMuted == true }))
        shared = microphone
        InUseMarksModule.shared = marks
        return [
            .init(requires: [.island, .microphoneMute], module: microphone),
            .init(requires: [.island, .inUseMarks], module: marks),
        ]
    }
}

extension InUseMarksModule {
    static fileprivate(set) var shared: InUseMarksModule?
}
