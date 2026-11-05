// notchcast-sources: Tinycast/Features/DictationTrigger/Model/*.swift
// notchcast-sources: Tinycast/Features/DictationTrigger/Service/*.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationCapture.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationSpectrum.swift
// notchcast-sources: Tinycast/Features/Notchcast/Input/EventTapPolicy.swift
import AppKit
import Carbon.HIToolbox
import Synchronization

@main
@MainActor
struct DictationTriggerTest {
    static func main() async throws {
        testEngine()
        try await testEvents()
        try await testCaptureStart()
        try await testCaptureStop()
        print("ALL PASSED: Globe tap/hold, chord isolation, preserved text, bounded capture start and stop")
    }

    private static func testEngine() {
        var engine = DictationTriggerEngine()
        expect(engine.handle(.down(isRecording: false), at: 0) == nil, "Provisional Globe does not capture")
        expect(engine.handle(.up, at: 0.1) == .start, "One solo tap starts recording")
        expect(engine.handle(.down(isRecording: true), at: 0.2) == nil, "Next tap reuses the recording")
        expect(engine.handle(.up, at: 0.3) == .finish, "Second tap finishes")

        expect(engine.handle(.down(isRecording: false), at: 1) == nil, "Hold awaits confirmation")
        expect(engine.handle(.confirm, at: 1.35) == .start, "Confirmed hold begins capture")
        expect(engine.handle(.up, at: 1.4) == .finish, "Hold past 350 ms finishes on release")
        expect(engine.handle(.down(isRecording: false), at: 2) == nil, "Tap after hold waits for release")
        expect(engine.handle(.up, at: 2.1) == .start, "Hold then tap toggles on")
        expect(engine.handle(.reset, at: 0) == .finish, "Switch-off finishes a toggled recording")

        _ = engine.handle(.down(isRecording: false), at: 0)
        expect(engine.handle(.down(isRecording: false), at: 0.3) == nil, "Repeated down cannot restart the clock")
        expect(engine.handle(.confirm, at: 0.35) == .start, "Exactly 350 ms confirms a hold")
        expect(engine.handle(.up, at: 0.35) == .finish, "Exactly 350 ms is a hold")
        _ = engine.handle(.down(isRecording: false), at: 0)
        expect(engine.handle(.up, at: 0.349) == .start, "Below 350 ms is a tap")
        _ = engine.handle(.reset, at: 0)
        _ = engine.handle(.down(isRecording: false), at: 0)
        expect(engine.handle(.otherInput, at: 0.1) == nil, "A chord never begins capture")
        expect(engine.handle(.up, at: 0.5) == nil, "Cancelled release cannot toggle")
        _ = engine.handle(.down(isRecording: false), at: 0)
        _ = engine.handle(.confirm, at: 0.35)
        expect(engine.handle(.otherInput, at: 5) == .finish, "A click after talking preserves dictation")

        _ = engine.handle(.down(isRecording: true), at: 1)
        expect(engine.handle(.otherInput, at: 1.1) == nil, "A chord preserves a prior toggled recording")
        _ = engine.handle(.down(isRecording: false), at: 2)
        expect(engine.handle(.finish, at: 2.2) == .finish, "Escape finishes instead of discarding")
        expect(engine.handle(.up, at: 2.3) == nil, "Escape consumes the pending release")
        _ = engine.handle(.down(isRecording: false), at: 3)
        expect(engine.handle(.reset, at: 0) == nil, "Pausing a provisional press has no capture effects")
        expect(engine.handle(.up, at: 4) == nil, "Pause drops a stale release")
    }

    private static func testEvents() async throws {
        let hub = EventTapHub()
        var recording = false
        var actions: [DictationTriggerEngine.Action] = []
        let manager = DictationTriggerManager(hub: hub, isRecording: { recording }) { action in
            actions.append(action)
            recording = action == .start
        }
        manager.setEnabled(true)
        manager.setEnabled(true)
        expect(hub.handlers.count == 1, "Enabling twice registers once on the shared hub")
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 0)
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 0.1)
        hub.send(.keyDown, key: 179, at: 0.11)
        expect(actions == [.start] && recording, "Globe's trailing key 179 cannot cancel a tap")
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 1)
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 1.1)
        expect(actions == [.start, .finish], "A second physical tap toggles off")

        actions = []
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 2)
        hub.send(.keyDown, key: kVK_ForwardDelete, flags: .maskSecondaryFn, at: 2.1)
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 2.5)
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 2.6)
        expect(actions.isEmpty, "Fn Delete never captures or rearms a held Globe")
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 2.7)
        hub.send(.keyDown, key: kVK_LeftArrow, flags: .maskSecondaryFn, at: 2.8)
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 2.9)
        expect(actions.isEmpty, "Fn arrow never captures")

        actions = []
        hub.send(.keyDown, key: kVK_F1, flags: .maskSecondaryFn, at: 3)
        hub.send(.flagsChanged, key: kVK_Shift, flags: .maskAlphaShift, at: 3.1)
        expect(actions.isEmpty, "Function-key fn residue and Caps Lock cannot start dictation")
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 4)
        try await wait { actions == [.start] }
        hub.send(.keyDown, key: kVK_ANSI_A, at: 4.1, isRepeat: true)
        hub.send(.keyDown, key: kVK_ANSI_A, at: 4.2, isSynthetic: true)
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 4.5)
        expect(actions == [.start, .finish], "Repeats and our synthetic typing leave a hold alone")

        for key in [kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter] {
            actions = []
            hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 5)
            try await wait { actions == [.start] }
            hub.send(.keyDown, key: key, at: 5.1)
            hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 5.2)
            expect(actions == [.start, .finish], "Finish keys preserve audio and suppress release toggling")
        }
        actions = []
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 6)
        try await wait { actions == [.start] }
        hub.send(.flagsChanged, key: kVK_Shift, flags: [.maskSecondaryFn, .maskShift], at: 6.4)
        hub.send(.flagsChanged, key: kVK_Shift, flags: .maskSecondaryFn, at: 6.5)
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 6.6)
        expect(actions == [.start, .finish], "Another modifier finishes a confirmed hold")
        actions = []
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 7)
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 7.1)
        manager.setEnabled(true, isPaused: true)
        expect(actions == [.start, .finish] && hub.handlers.isEmpty,
               "Pausing finishes a toggled recording and removes its consumer")
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 7.5)
        expect(actions == [.start, .finish], "An unregistered consumer receives no stale release")
        actions = []
        var temporary: DictationTriggerManager? = DictationTriggerManager(hub: hub, isRecording: { false }) {
            actions.append($0)
        }
        temporary?.setEnabled(true)
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 8)
        try await wait { actions == [.start] }
        temporary = nil
        expect(actions == [.start, .finish] && hub.handlers.isEmpty, "Owner teardown preserves provisional audio")
    }

    private static func testCaptureStart() async throws {
        let stops = Mutex(0)
        try await DictationCapture.startBounded(start: { true }, stop: { stops.withLock { $0 += 1 } })
        expect(stops.withLock { $0 } == 0, "Successful capture stays open")
        do {
            try await DictationCapture.startBounded(start: { false }, stop: {})
            preconditionFailure("Failed start must throw")
        } catch DictationCapture.Failure.captureUnavailable {
            expect(true, "Ordinary start failure retains its generic microphone error")
        }

        let release = DispatchSemaphore(value: 0)
        let finished = Mutex(false)
        do {
            try await DictationCapture.startBounded(
                timeout: .milliseconds(30), start: { release.wait(); return true },
                stop: { finished.withLock { $0 = true } })
            preconditionFailure("Hung start must time out")
        } catch DictationCapture.Failure.coreAudioUnresponsive {
            let message = DictationCapture.Failure.coreAudioUnresponsive.localizedDescription
            expect(message.contains("coreaudiod"), "The timeout names coreaudiod")
        }
        release.signal()
        try await wait { finished.withLock { $0 } }
        expect(true, "Late success is stopped rather than leaking microphone capture")

        let entered = Mutex(false)
        let cancelledRelease = DispatchSemaphore(value: 0)
        let cancelledStopped = Mutex(false)
        let task = Task {
            try await DictationCapture.startBounded(
                start: { entered.withLock { $0 = true }; cancelledRelease.wait(); return true },
                stop: { cancelledStopped.withLock { $0 = true } })
        }
        try await wait { entered.withLock { $0 } }
        task.cancel()
        do { try await task.value; preconditionFailure("Cancellation must return") } catch is CancellationError {}
        cancelledRelease.signal()
        try await wait { cancelledStopped.withLock { $0 } }
        expect(true, "Cancellation returns promptly and closes a late start")
    }

    private static func testCaptureStop() async throws {
        let stopped = Mutex(false)
        await DictationCapture.stopBounded { stopped.withLock { $0 = true } }
        expect(stopped.withLock { $0 }, "A prompt stop runs before stop returns")

        let release = DispatchSemaphore(value: 0)
        let clock = ContinuousClock()
        let started = clock.now
        await DictationCapture.stopBounded(timeout: .milliseconds(30)) { release.wait() }
        expect(clock.now - started < .seconds(2), "A hung coreaudiod stop returns within its bound")
        release.signal()

        let entered = Mutex(false)
        let cancelledRelease = DispatchSemaphore(value: 0)
        let returned = Mutex(false)
        let task = Task {
            await DictationCapture.stopBounded(timeout: .seconds(10)) {
                entered.withLock { $0 = true }
                cancelledRelease.wait()
            }
            returned.withLock { $0 = true }
        }
        try await wait { entered.withLock { $0 } }
        task.cancel()
        try await Task.sleep(for: .milliseconds(50))
        expect(!returned.withLock { $0 }, "Cancellation cannot skip a stop still in progress")
        cancelledRelease.signal()
        await task.value
        expect(returned.withLock { $0 }, "A cancelled stop returns once the session stops")
    }

    private static func wait(_ condition: () -> Bool) async throws {
        while !condition() {
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func expect(_ value: Bool, _ message: String) {
        precondition(value, message)
        print("PASS  \(message)")
    }
}

enum DictationWire {
    static let sampleRate = 16_000
    static let maximumSamples = sampleRate * 60 * 5
}

@MainActor
final class EventTapHub {
    struct Event: Sendable {
        let type: CGEventType
        let flags: CGEventFlags
        let keyCode: Int64
        let isRepeat: Bool
        let isSynthetic: Bool
        let timestamp: CGEventTimestamp
    }

    private(set) var handlers: [UUID: @MainActor @Sendable (Event) -> Void] = [:]

    func register(mask: CGEventMask, handler: @escaping @MainActor @Sendable (Event) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    func remove(_ id: UUID) { handlers[id] = nil }

    func send(
        _ type: CGEventType, key: Int, flags: CGEventFlags = [], at time: TimeInterval,
        isRepeat: Bool = false, isSynthetic: Bool = false
    ) {
        let event = Event(
            type: type, flags: flags, keyCode: Int64(key), isRepeat: isRepeat,
            isSynthetic: isSynthetic, timestamp: UInt64(time * 1_000_000_000))
        for handler in handlers.values { handler(event) }
    }
}
