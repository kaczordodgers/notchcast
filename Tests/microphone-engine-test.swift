// notchcast-sources: Tinycast/Features/Microphone/Model/*.swift
import Foundation

@MainActor
private final class FakeMicrophoneAudio: MicrophoneAudioAccess {
    var monitoringFailure: MicrophoneInput.Failure?
    var devices: [MicrophoneInput] = [
        .init(id: 1, uid: "builtin", mute: [], volume: [.init(element: 0, value: 0.62)]),
        .init(id: 2, uid: "usb", mute: [.init(element: 0, value: 0)], volume: [.init(element: 0, value: 0.4)]),
        .init(id: 3, uid: "stereo", mute: [], volume: [.init(element: 1, value: 0.3), .init(element: 2, value: 0.7)])
    ]
    var change: (@MainActor () -> Void)?
    var beforeWrite: (() -> Void)?
    var refuseMute = false
    var refuseVolume = false
    var appliesWrite = true
    var readFailure = false
    var writes = 0

    func inputs() throws(MicrophoneInput.Failure) -> [MicrophoneInput] {
        if readFailure { throw .read(-1) }
        return devices
    }

    func write(_ levels: [MicrophoneInput.Level], control: MicrophoneInput.Control,
               on input: MicrophoneInput) throws(MicrophoneInput.Failure) {
        beforeWrite?()
        if (control == .mute && refuseMute) || (control == .volume && refuseVolume) {
            throw .write(input.uid, -2)
        }
        guard let index = devices.firstIndex(where: { $0.id == input.id && $0.uid == input.uid }) else {
            throw .unavailable(input.uid)
        }
        writes += 1
        guard appliesWrite else { return }
        if control == .mute { devices[index].mute = levels } else { devices[index].volume = levels }
    }

    func start(change: @escaping @MainActor () -> Void) { self.change = change }
    func stop() { change = nil }
}

@main @MainActor
struct MicrophoneEngineTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        engineTests()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func engineTests() {
        let suite = "microphone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FakeMicrophoneAudio()
        let initial = backend.devices
        var engine = MicrophoneMute(audio: backend, defaults: defaults)
        engine.start()
        expect(backend.writes == 0, "launch preserves an unmuted microphone")
        var savedBeforeWrite = true
        backend.beforeWrite = {
            savedBeforeWrite = savedBeforeWrite && defaults.data(forKey: "microphone.muted.restore") != nil
        }
        engine.setMuted(true)
        expect(savedBeforeWrite, "restore state is persisted before touching controls")
        expect(engine.isMuted && backend.devices.allSatisfy(\.isMuted), "every input is muted")
        expect(backend.devices[1].volume == initial[1].volume, "hardware mute preserves input gain")
        expect(defaults.bool(forKey: "microphone.muted"), "mute intent is persisted at the specified key")
        let writes = backend.writes
        engine.setMuted(true)
        backend.change?()
        expect(backend.writes == writes, "repeated mute and listener echoes do not rewrite controls")
        engine.stop()
        engine = MicrophoneMute(audio: backend, defaults: defaults)
        engine.start()
        expect(engine.isMuted, "mute survives relaunch")
        backend.devices.append(.init(id: 4, uid: "new", mute: [], volume: [.init(element: 0, value: 0.81)]))
        backend.change?()
        expect(backend.devices.last?.isMuted == true, "new input is muted without becoming the default")
        backend.devices[0].volume[0] = .init(element: 0, value: 0.9)
        backend.change?()
        expect(backend.devices[0].isMuted, "external changes reapply a requested mute")
        engine.toggle()
        expect(!engine.isMuted && !defaults.bool(forKey: "microphone.muted"), "toggle clears persisted intent")
        expect(Array(backend.devices.prefix(3)) == initial, "unmute restores each exact previous channel level")
        expect(backend.devices[3].volume[0].value == 0.81, "new input's level is restored")
        print("mute engine: restore previous level, relaunch persistence, device change re-applies mute PASS")

        engine.setMuted(true)
        let disconnected = backend.devices.remove(at: 2)
        engine.setMuted(false)
        engine.stop()
        engine = MicrophoneMute(audio: backend, defaults: defaults)
        engine.start()
        backend.devices.append(.init(id: 93, uid: disconnected.uid, mute: [], volume: disconnected.volume))
        backend.change?()
        expect(backend.devices.last?.volume == initial[2].volume, "reconnected device restores by UID after relaunch")

        backend.refuseMute = true
        engine.setMuted(true)
        expect(engine.isMuted && engine.failures.isEmpty, "failed hardware mute falls back to volume")
        backend.refuseMute = false
        engine.setMuted(true)
        engine.setMuted(false)
        expect(backend.devices[1].volume == initial[1].volume, "fallback keeps its original gain record")

        backend.refuseVolume = true
        engine.setMuted(true)
        expect(!engine.isMuted && !engine.failures.isEmpty, "partial mute exposes a typed failure")
        backend.refuseVolume = false
        backend.change?()
        expect(engine.isMuted, "a subsequent device event retries failed mute")
        backend.refuseVolume = true
        engine.setMuted(false)
        expect(!engine.failures.isEmpty, "failed restore is reported")
        backend.refuseVolume = false
        backend.change?()
        expect(backend.devices[0].volume == initial[0].volume, "failed restore keeps its record for retry")

        backend.devices.append(.init(id: 5, uid: "unsupported", mute: [], volume: []))
        engine.setMuted(true)
        expect(engine.failures.contains(.unsupported("unsupported")), "unsupported input is identified")
        expect(!engine.isMuted, "an unsupported input cannot report all inputs muted")
        engine.setMuted(false)
        backend.devices.removeLast()
        engine.setMuted(true)
        backend.devices[0].volume = [.init(element: 8, value: 0)]
        engine.setMuted(false)
        expect(engine.failures.contains(.changedControls("builtin")), "changed topology never restores to wrong channels")
        backend.devices[0].volume = [.init(element: 0, value: 0)]
        backend.change?()
        expect(backend.devices[0].volume == initial[0].volume, "restore record survives a topology mismatch")
        backend.readFailure = true
        backend.change?()
        expect(engine.failures == [.read(-1)] && !engine.isMuted, "read errors clear confirmed mute state")
        backend.readFailure = false
        let lateCallback = backend.change
        engine.stop()
        let stoppedWrites = backend.writes
        lateCallback?()
        expect(backend.writes == stoppedWrites && backend.change == nil, "stop removes listeners and ignores queued callbacks")

        let empty = FakeMicrophoneAudio()
        empty.devices = []
        let noInputs = MicrophoneMute(audio: empty, defaults: defaults, key: "empty.muted")
        noInputs.setMuted(true)
        expect(noInputs.failures == [.noInputs] && !noInputs.isMuted, "missing inputs cannot report mute success")

        let delayed = FakeMicrophoneAudio()
        let delayedInitial = delayed.devices
        let delayedMute = MicrophoneMute(audio: delayed, defaults: defaults, key: "delayed.muted")
        delayedMute.setMuted(true)
        delayed.appliesWrite = false
        delayedMute.toggle()
        expect(delayedMute.isMuted && !defaults.bool(forKey: "delayed.muted"),
               "confirmed state can lag behind an accepted unmute")
        delayedMute.toggle()
        expect(defaults.bool(forKey: "delayed.muted"), "a quick second toggle follows intent despite delayed confirmation")
        delayed.appliesWrite = true
        delayedMute.setMuted(false)
        expect(delayed.devices == delayedInitial, "unconfirmed restoration retains original levels through a quick remute")

        defaults.set(Data("broken".utf8), forKey: "microphone.muted.restore")
        let corrupt = MicrophoneMute(audio: backend, defaults: defaults)
        corrupt.setMuted(true)
        expect(corrupt.failures == [.invalidSavedLevels], "corrupt restore data reports a typed failure")
        expect(corrupt.isMuted, "corrupt restore data does not block muting")
        corrupt.setMuted(false)
        expect(corrupt.failures.isEmpty, "corrupt restore failure is reported only once")

        for data in [Data("broken".utf8), Data(#"{"usb":{"volume":{"_0":[{"element":0,"value":2}]}}}"#.utf8)] {
            defaults.set(data, forKey: "corrupt.restore")
            let recovery = FakeMicrophoneAudio()
            recovery.devices[1].mute = [.init(element: 0, value: 1)]
            let before = recovery.devices
            let recovered = MicrophoneMute(audio: recovery, defaults: defaults, key: "corrupt")
            recovered.setMuted(false)
            expect(recovered.failures == [.invalidSavedLevels], "unmute reports invalid saved data once")
            expect(defaults.data(forKey: "corrupt.restore") == nil, "invalid saved data is removed")
            expect(recovery.devices == before, "unmute without records preserves every device")
            recovered.setMuted(true)
            recovered.setMuted(false)
            expect(recovery.devices == before, "preexisting mute survives a mute and restore cycle")
            expect(recovered.failures.isEmpty, "later requests recover from invalid saved data")
        }

        backend.monitoringFailure = .read(-99)
        engine.start()
        expect(engine.failures.contains(.read(-99)), "listener failure reaches mute state")
        backend.monitoringFailure = nil
        backend.change?()
        expect(!engine.failures.contains(.read(-99)), "successful registration clears mute listener failure")
    }
}
