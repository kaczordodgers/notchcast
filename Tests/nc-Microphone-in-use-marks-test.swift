import Foundation
import CoreAudio
import CoreMediaIO

@MainActor
private enum ListenerFixture {
    static var live: Bool {
        CommandLine.arguments.contains("--live-audio") || CommandLine.arguments.contains("--live-marks")
    }
    static var audioStatus: OSStatus = -81
    static var cameraStatus: OSStatus = -82
    static var audioCallbacks: [AudioObjectPropertyListenerBlock] = []
    static var cameraCallbacks: [CMIOObjectPropertyListenerBlock] = []
}

@MainActor
func AudioObjectGetPropertyDataSize(
    _ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>
) -> OSStatus {
    if ListenerFixture.live {
        return CoreAudio.AudioObjectGetPropertyDataSize(object, address, qualifierSize, qualifier, size)
    }
    size.pointee = 0
    return ListenerFixture.audioStatus
}

@MainActor
func CMIOObjectGetPropertyDataSize(
    _ object: CMIOObjectID, _ address: UnsafePointer<CMIOObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>
) -> OSStatus {
    if ListenerFixture.live {
        return CoreMediaIO.CMIOObjectGetPropertyDataSize(object, address, qualifierSize, qualifier, size)
    }
    size.pointee = 0
    return ListenerFixture.cameraStatus
}

@MainActor
func AudioObjectAddPropertyListenerBlock(
    _ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ queue: DispatchQueue?, _ block: @escaping AudioObjectPropertyListenerBlock
) -> OSStatus {
    if ListenerFixture.live { return CoreAudio.AudioObjectAddPropertyListenerBlock(object, address, queue, block) }
    ListenerFixture.audioCallbacks.append(block)
    return noErr
}

@MainActor
@discardableResult
func AudioObjectRemovePropertyListenerBlock(
    _ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ queue: DispatchQueue?, _ block: @escaping AudioObjectPropertyListenerBlock
) -> OSStatus {
    if ListenerFixture.live { return CoreAudio.AudioObjectRemovePropertyListenerBlock(object, address, queue, block) }
    return noErr
}

@MainActor
func CMIOObjectAddPropertyListenerBlock(
    _ object: CMIOObjectID, _ address: UnsafePointer<CMIOObjectPropertyAddress>,
    _ queue: DispatchQueue?, _ block: @escaping CMIOObjectPropertyListenerBlock
) -> OSStatus {
    if ListenerFixture.live { return CoreMediaIO.CMIOObjectAddPropertyListenerBlock(object, address, queue, block) }
    ListenerFixture.cameraCallbacks.append(block)
    return noErr
}

@MainActor
@discardableResult
func CMIOObjectRemovePropertyListenerBlock(
    _ object: CMIOObjectID, _ address: UnsafePointer<CMIOObjectPropertyAddress>,
    _ queue: DispatchQueue?, _ block: @escaping CMIOObjectPropertyListenerBlock
) -> OSStatus {
    if ListenerFixture.live { return CoreMediaIO.CMIOObjectRemovePropertyListenerBlock(object, address, queue, block) }
    return noErr
}

@MainActor
private final class FakeInUseSource: InUseSource {
    var monitoringFailure: MicrophoneInput.Failure?
    var reading = InUseReading()
    var change: (@MainActor () -> Void)?
    var reads: [TimeInterval] = []
    var now: TimeInterval = 0
    var fail = false
    var starts = 0
    var stops = 0

    func start(change: @escaping @MainActor () -> Void) {
        self.change = change
        starts += 1
    }

    func stop() {
        change = nil
        stops += 1
    }

    func read() throws(MicrophoneInput.Failure) -> InUseReading {
        reads.append(now)
        if fail { throw .read(-12) }
        return reading
    }
}

@MainActor
private final class ManualMarksClock {
    struct Pending {
        var deadline: TimeInterval
        var cancelled = false
        let action: @MainActor () -> Void
    }
    var now: TimeInterval = 0
    var work: [Pending] = []

    func schedule(_ delay: TimeInterval, action: @escaping @MainActor () -> Void) -> (() -> Void) {
        let index = work.count
        work.append(.init(deadline: now + delay, action: action))
        return { self.work[index].cancelled = true }
    }

    func advance(to next: TimeInterval, source: FakeInUseSource) {
        now = next
        source.now = next
        for index in work.indices where !work[index].cancelled && work[index].deadline <= next {
            work[index].cancelled = true
            work[index].action()
        }
    }
}

@main @MainActor
struct InUseMarksTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        if CommandLine.arguments.contains("--live-audio") {
            try await liveAudio()
            return
        }
        if CommandLine.arguments.contains("--live-marks") {
            try await liveMarks()
            return
        }
        await listenerRecovery()
        let source = FakeInUseSource()
        let clock = ManualMarksClock()
        var muted = false
        var marks: InUseMarks? = InUseMarks(source: source, now: { clock.now }, schedule: clock.schedule, isMuted: { muted })
        expect(source.starts == 0 && source.reads.isEmpty, "disabled marks do no hardware work")
        marks!.setEnabled(true)
        marks!.setEnabled(true)
        expect(source.starts == 1 && source.reads == [0], "enable starts once and immediately reads")
        source.reading = .init(camera: true, microphone: true, micApps: ["app.b", "app.a", "app.b", ""])
        for _ in 0..<100 { source.change?() }
        expect(source.reads.count == 1 && clock.work.count == 1, "burst coalesces into one pending read")
        clock.advance(to: 0.99, source: source)
        expect(!marks!.camera, "no second read within a second")
        clock.advance(to: 1, source: source)
        expect(marks!.camera && marks!.microphone, "coalesced read applies camera and microphone")
        expect(marks!.micApps == ["app.a", "app.b"], "app bundle ids are unique and stable")
        expect(source.reads == [0, 1], "reads are at most once per second")
        muted = true
        expect(marks!.isMuted, "mute state is exposed independently of recording apps")
        source.reading = .init(microphone: true)
        clock.advance(to: 5, source: source)
        source.change?()
        expect(marks!.microphone && marks!.micApps.isEmpty, "recording without a bundle id still marks microphone in use")
        expect(!marks!.camera, "idle source clears camera mark")
        source.change?()
        let staleChange = source.change
        let staleWork = clock.work.last!.action
        marks!.setEnabled(false)
        expect(!marks!.camera && !marks!.microphone && !marks!.isMuted && marks!.micApps.isEmpty,
               "disable clears every exposed mark")
        let count = source.reads.count
        staleChange?()
        staleWork()
        clock.advance(to: 5.1, source: source)
        marks!.setEnabled(true)
        staleWork()
        expect(source.reads.count == count, "disable and reenable preserve throttle and reject stale callbacks")
        clock.advance(to: 6, source: source)
        expect(source.reads.count == count + 1, "reenable performs a fresh throttled read")
        source.fail = true
        clock.advance(to: 7, source: source)
        source.change?()
        expect(marks!.failure == .read(-12) && !marks!.microphone, "read errors expose typed failure and clear stale marks")
        source.fail = false
        source.change?()
        clock.advance(to: 8, source: source)
        expect(marks!.failure == nil && marks!.microphone, "a later event recovers from read failure")
        source.monitoringFailure = .read(-99)
        source.change?()
        clock.advance(to: 9, source: source)
        expect(marks!.failure == .read(-99), "registration failure reaches marks")
        source.monitoringFailure = nil
        source.change?()
        clock.advance(to: 10, source: source)
        expect(marks!.failure == nil, "successful registration clears marks failure")
        marks = nil
        expect(source.change == nil, "deinit stops the source")
        print("in-use marks: coalescing <= 1 update/second, cancellation, bundle ids, mute state PASS")
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static func listenerRecovery() async {
        let audio = CoreMicrophoneAudio()
        audio.start {}
        expect(audio.monitoringFailure == .read(-81), "audio enumeration failure is reported")
        ListenerFixture.audioStatus = noErr
        var address = MicrophoneAudioObject.address(kAudioHardwarePropertyDevices)
        ListenerFixture.audioCallbacks[0](1, &address)
        for _ in 0..<10 { await Task.yield() }
        expect(audio.monitoringFailure == nil, "audio listener rebuild clears recovered failure")
        audio.stop()
        ListenerFixture.audioCallbacks = []
        ListenerFixture.audioStatus = -81
        let source = SystemInUseSource()
        source.start {}
        expect(source.monitoringFailure == .read(-81), "process enumeration failure is reported")
        ListenerFixture.audioStatus = noErr
        ListenerFixture.audioCallbacks[0](1, &address)
        for _ in 0..<10 { await Task.yield() }
        expect(source.monitoringFailure == .read(-82), "process recovery preserves camera failure")
        ListenerFixture.cameraStatus = noErr
        var cameraAddress = CMIOObjectPropertyAddress()
        ListenerFixture.cameraCallbacks[0](1, &cameraAddress)
        for _ in 0..<10 { await Task.yield() }
        expect(source.monitoringFailure == nil, "camera listener rebuild clears recovered failure")
        source.stop()
    }

    private static func liveAudio() async throws {
        let audio = CoreMicrophoneAudio()
        let before = try audio.inputs()
        guard !before.isEmpty else { throw MicrophoneInput.Failure.unavailable("inputs") }
        let suite = "microphone-live-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let mute = MicrophoneMute(audio: audio, defaults: defaults)
        defer {
            mute.setMuted(false)
            mute.stop()
            for input in before {
                do {
                    if !input.mute.isEmpty { try audio.write(input.mute, control: .mute, on: input) }
                    if !input.volume.isEmpty { try audio.write(input.volume, control: .volume, on: input) }
                } catch { print("LIVE cleanup failed: \(error)") }
            }
            defaults.removePersistentDomain(forName: suite)
        }
        mute.start()
        mute.setMuted(true)
        try await Task.sleep(for: .seconds(1))
        let muted = try audio.inputs()
        for input in muted {
            print("LIVE input uid=\(input.uid) muted=\(input.isMuted) mute=\(input.mute) volume=\(input.volume)")
        }
        let allMuted = !muted.isEmpty && muted.allSatisfy(\.isMuted)
        print("LIVE every input device muted=\(allMuted) count=\(muted.count) failures=\(mute.failures)")
        expect(allMuted && mute.isMuted && mute.failures.isEmpty, "live mute readback")
        mute.setMuted(false)
        try await Task.sleep(for: .seconds(1))
        let restored = try audio.inputs()
        let levelsRestored = before.allSatisfy { old in
            restored.first(where: { $0.uid == old.uid })?.volume == old.volume
        }
        let unmuted = restored.allSatisfy { $0.mute.allSatisfy { $0.value == 0 } }
        print("LIVE unmute restores previous levels=\(levelsRestored) hardware unmuted=\(unmuted)")
        expect(levelsRestored && unmuted, "live unmute readback")
        expect(audio.monitoringFailure == nil, "native mute listeners installed")
        if failures > 0 { throw MicrophoneInput.Failure.write("live-check", -1) }
    }

    private static func liveMarks() async throws {
        let source = SystemInUseSource()
        let marks = InUseMarks(source: source, isMuted: { false })
        marks.setEnabled(true)
        defer { marks.setEnabled(false) }
        for _ in 0..<12 {
            try await Task.sleep(for: .seconds(1))
            print("LIVE microphone=\(marks.microphone) micApps=\(marks.micApps) failure=\(String(describing: marks.failure))")
            if marks.microphone && !marks.micApps.isEmpty {
                expect(source.monitoringFailure == nil, "native marks listeners installed")
                if failures > 0 { throw MicrophoneInput.Failure.read(-1) }
                print("SKIP: live camera capture: no camera opened or permission requested")
                return
            }
        }
        throw MicrophoneInput.Failure.unavailable("recording process bundle id")
    }
}
