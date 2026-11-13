// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityManager.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityTransport.swift
// notchcast-sources: Tinycast/Features/Microphone/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift Tinycast/Platform/AppPaths.swift
import Foundation

@MainActor
private final class Audio: AudioPriorityTransport {
    struct Failure: Error {}
    var callback: (@Sendable () -> Void)?
    var failStart = false
    var starts = 0
    var current = "low"
    var hasInput = false
    var reads = 0
    var failSwitch = false
    var outputs = ["low", "high"]
    var inputSwitches = 0
    func devices() -> [AudioPriorityDevice] {
        reads += 1
        return outputs.map { .init(uid: $0, name: $0, direction: .output) }
            + (hasInput ? [.init(uid: "mic", name: "mic", direction: .input)] : [])
    }
    func defaultUID(for direction: AudioPriorityDevice.Direction) -> String? { current }
    func setDefault(uid: String, for direction: AudioPriorityDevice.Direction) throws {
        if failSwitch && direction == .output { throw Failure() }
        if direction == .output { current = uid }
        if direction == .input { inputSwitches += 1 }
    }
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
        manager.stop()
        check(store.failure == nil, "failure cleared on stop")
        store.failure = "old"
        manager.start()
        check(store.failure == nil, "failure cleared on start")
        store.save(.init(enabled: true, uids: ["high", "low"]), for: .output)
        await settle { audio.current == "high" }
        check(audio.current == "high", "ranking applied without device change")
        manager.stop()
        manager.start()
        audio.current = "low"
        store.failure = "unresolved"
        audio.hasInput = true
        let inputReads = audio.reads
        audio.callback?()
        await settle { audio.reads >= inputReads + 2 }
        check(audio.current == "low", "new input preserves hand-picked output")
        check(store.failure == "unresolved", "device event preserves unresolved failure")
        store.move("low", by: -1, direction: .output)
        let moveReads = audio.reads
        await settle { audio.reads > moveReads }
        check(audio.current == "low", "reordered ranking applied")
        audio.failSwitch = true
        store.move("high", by: -1, direction: .output)
        let failureReads = audio.reads
        await settle { audio.reads > failureReads }
        check(store.failure == "failure", "failed switch reports failure")
        audio.failSwitch = false
        store.move("low", by: -1, direction: .output)
        let reorderReads = audio.reads
        await settle { audio.reads > reorderReads }
        store.move("high", by: -1, direction: .output)
        await settle { audio.current == "high" }
        check(store.failure == nil, "successful switch clears previous failure")
        manager.stop()
        audio.hasInput = false
        store.save(.init(enabled: true, uids: ["high", "low", "usb"]), for: .output)
        store.save(.init(enabled: true, uids: ["mic"]), for: .input)
        manager.start()
        audio.current = "low"
        audio.failSwitch = true
        audio.outputs.append("usb")
        audio.hasInput = true
        let inputSwitches = audio.inputSwitches
        audio.callback?()
        await settle { audio.inputSwitches > inputSwitches }
        check(store.failure != nil, "successful input switch preserves output failure in same refresh")
        audio.failSwitch = false
        manager.stop()
        audio.failStart = true
        manager.start()
        let starts = audio.starts
        audio.failStart = false
        audio.callback?()
        await settle { audio.starts == starts + 1 }
        check(audio.starts == starts + 1, "failed start retried on device change")
        manager.stop()
        audio.failStart = true
        manager.start()
        let restartStarts = audio.starts
        manager.stop()
        audio.failStart = false
        manager.start()
        check(audio.starts == restartStarts + 1, "failed start retried on restart")
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
    @MainActor private static func settle(until ready: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !ready(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        precondition(ready(), "Audio refresh did not arrive")
    }
    @MainActor private static func check(_ condition: Bool, _ name: String) {
        print("\(condition ? "PASS" : "FAIL"): \(name)")
        failed = failed || !condition
    }
}
