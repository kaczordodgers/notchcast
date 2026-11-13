// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityManager.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityTransport.swift
// notchcast-sources: Tinycast/Features/Microphone/Model/*.swift
import Foundation

@MainActor
private final class Audio: AudioPriorityTransport {
    struct Failure: Error {}
    var callback: (@Sendable () -> Void)?
    var failStart = false
    var starts = 0
    var current = "low"
    func devices() -> [AudioPriorityDevice] {
        ["low", "high"].map { .init(uid: $0, name: $0, direction: .output) }
    }
    func defaultUID(for direction: AudioPriorityDevice.Direction) -> String? { current }
    func setDefault(uid: String, for direction: AudioPriorityDevice.Direction) { current = uid }
    func start(onChange: @escaping @Sendable () -> Void) throws {
        starts += 1
        callback = onChange
        if failStart { throw Failure() }
    }
    func stop() { callback = nil }
}

@MainActor
private final class Mic: MicrophoneAudioAccess {
    var monitoringFailure: MicrophoneInput.Failure?
    var input = MicrophoneInput(id: 1, uid: "mic", mute: [.init(element: 0, value: 1)], volume: [])
    func inputs() throws(MicrophoneInput.Failure) -> [MicrophoneInput] { [input] }
    func write(_ levels: [MicrophoneInput.Level], control: MicrophoneInput.Control,
               on input: MicrophoneInput) throws(MicrophoneInput.Failure) { self.input.mute = levels }
    func start(change: @escaping @MainActor () -> Void) {}
    func stop() {}
}

@main
struct RecoveryTests {
    @MainActor
    static func main() async throws {
        let suite = "audio-recovery-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AudioPriorityPreferences(suiteName: suite)
        let audio = Audio()
        let manager = AudioPriorityManager(transport: audio, store: store) { _ in store.failure = "failure" }
        manager.clearFailure = { store.failure = nil }
        manager.start()
        store.failure = "old"
        manager.refresh()
        check(store.failure == nil, "failure cleared on refresh")
        store.failure = "old"
        manager.stop()
        check(store.failure == nil, "failure cleared on stop")
        store.failure = "old"
        manager.start()
        check(store.failure == nil, "failure cleared on start")
        store.save(.init(enabled: true, uids: ["high", "low"]), for: .output)
        try await Task.sleep(for: .milliseconds(180))
        check(audio.current == "high", "ranking applied without device change")
        store.move("low", by: -1, direction: .output)
        try await Task.sleep(for: .milliseconds(180))
        check(audio.current == "low", "reordered ranking applied")
        manager.stop()
        audio.failStart = true
        manager.start()
        let starts = audio.starts
        audio.failStart = false
        audio.callback?()
        try await Task.sleep(for: .milliseconds(180))
        check(audio.starts == starts + 1, "failed start retried on device change")
        manager.stop()
        audio.failStart = true
        manager.start()
        let refreshStarts = audio.starts
        audio.failStart = false
        manager.refresh()
        check(audio.starts == refreshStarts + 1, "failed start retried on refresh")
        manager.stop()
        let mic = Mic()
        let mute = MicrophoneMute(audio: mic, defaults: defaults)
        mute.start()
        check(mic.input.isMuted, "start preserves external mute")
        mute.setMuted(true)
        mute.setMuted(false)
        check(!mic.input.isMuted, "unmute previously muted microphone")
        mute.stop()
        if failed { fatalError("Recovery regressions failed") }
    }

    @MainActor private static var failed = false
    @MainActor private static func check(_ condition: Bool, _ name: String) {
        print("\(condition ? "PASS" : "FAIL"): \(name)")
        failed = failed || !condition
    }
}
