// notchcast-sources: Tinycast/Features/Microphone/Model/*.swift
import Foundation

@MainActor
final class FakeMicrophone: MicrophoneAudioAccess {
    var monitoringFailure: MicrophoneInput.Failure?
    var input = MicrophoneInput(id: 1, uid: "fixture", mute: [
        .init(element: 1, value: 1), .init(element: 2, value: 0)], volume: [])
    func inputs() throws(MicrophoneInput.Failure) -> [MicrophoneInput] { [input] }
    func write(_ levels: [MicrophoneInput.Level], control: MicrophoneInput.Control,
               on input: MicrophoneInput) throws(MicrophoneInput.Failure) {
        if control == .mute { self.input.mute = levels } else { self.input.volume = levels }
    }
    func start(change: @escaping @MainActor () -> Void) {}
    func stop() {}
}

@main @MainActor
struct MicrophoneMuteTests {
    static func main() {
        let suite = "microphone-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let audio = FakeMicrophone()
        let model = MicrophoneMute(audio: audio, defaults: defaults)
        model.setMuted(true)
        precondition(audio.input.mute.map(\.value) == [1, 1])
        model.stop()
        let restored = MicrophoneMute(audio: audio, defaults: defaults)
        restored.setMuted(false)
        precondition(audio.input.mute.map(\.value) == [1, 0], "Restore original per-channel mute")
        restored.stop()
        audio.input.mute = [.init(element: 1, value: 1), .init(element: 2, value: 1)]
        let afterRestore = MicrophoneMute(audio: audio, defaults: defaults)
        afterRestore.setMuted(false)
        precondition(audio.input.mute.map(\.value) == [1, 1], "A restored mute record is not replayed")
        afterRestore.stop()
        defaults.set(Data(#"{"fixture":{"mute":{}}}"#.utf8), forKey: "microphone.muted.restore")
        audio.input.mute = [.init(element: 1, value: 1), .init(element: 2, value: 1)]
        let legacy = MicrophoneMute(audio: audio, defaults: defaults)
        legacy.setMuted(false)
        precondition(audio.input.mute.map(\.value) == [0, 0])
        precondition(legacy.failures.isEmpty)
        legacy.stop()
        print("PASS: mixed channel mute restored across restart; legacy record restored")
    }
}
