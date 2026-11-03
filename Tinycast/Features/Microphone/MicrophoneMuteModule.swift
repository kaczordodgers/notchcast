import Foundation
import Observation

@MainActor
@Observable
final class MicrophoneMuteModule: NotchcastModule {
    let model: MicrophoneMute
    private(set) var isEnabled = false
    private let showMessage: (String) -> Void
    private let showFailure: (MicrophoneInput.Failure) -> Void

    init(model: MicrophoneMute, showMessage: @escaping (String) -> Void,
         showFailure: @escaping (MicrophoneInput.Failure) -> Void) {
        self.model = model
        self.showMessage = showMessage
        self.showFailure = showFailure
    }

    func start() {
        isEnabled = true
        model.start()
    }

    func stop() {
        isEnabled = false
        model.setMuted(false)
        if let failure = model.failures.first { showFailure(failure) }
        model.stop()
    }

    func toggle() {
        model.toggle()
        report()
        if !isEnabled { model.stop() }
    }

    func setMuted(_ muted: Bool) {
        model.setMuted(muted)
        report()
        if !isEnabled { model.stop() }
    }

    private func report() {
        if let failure = model.failures.first {
            showFailure(failure)
            return
        }
        showMessage(model.isMuted ? String(localized: "Microphone Muted") : String(localized: "Microphone Unmuted"))
    }
}
