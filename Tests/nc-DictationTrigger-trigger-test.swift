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
        testEvents()
        try await testCaptureStart()
        print("ALL PASSED: Globe tap/hold, pre-roll, cancellation, bounded capture start")
    }

    private static func testEngine() {
        var engine = DictationTriggerEngine()
        expect(engine.handle(.down(isRecording: false), at: 0) == .start, "Capture starts before hold decision")
        expect(engine.handle(.up, at: 0.1) == nil, "One tap leaves recording on")
        expect(engine.handle(.down(isRecording: true), at: 0.2) == nil, "Next tap reuses the recording")
        expect(engine.handle(.up, at: 0.3) == .finish, "Second tap finishes")

        expect(engine.handle(.down(isRecording: false), at: 1) == .start, "Hold records pre-roll immediately")
        expect(engine.handle(.up, at: 1.4) == .finish, "Hold past 350 ms finishes on release")
        expect(engine.handle(.down(isRecording: false), at: 2) == .start, "Tap after hold starts a new session")
        expect(engine.handle(.up, at: 2.1) == nil, "Hold then tap toggles on")

        _ = engine.handle(.down(isRecording: false), at: 0)
        expect(engine.handle(.down(isRecording: false), at: 0.3) == nil, "Repeated down cannot restart the clock")
        expect(engine.handle(.up, at: 0.35) == .finish, "Exactly 350 ms is a hold")
        _ = engine.handle(.down(isRecording: false), at: 0)
        expect(engine.handle(.up, at: 0.349) == nil, "Below 350 ms is a tap")
        _ = engine.handle(.down(isRecording: false), at: 0)
        expect(engine.handle(.otherInput, at: 0.4) == .cancel, "A chord cancels the provisional hold")
        expect(engine.handle(.up, at: 0.5) == nil, "Cancelled release cannot toggle")

        _ = engine.handle(.down(isRecording: true), at: 1)
        expect(engine.handle(.otherInput, at: 1.1) == nil, "A chord preserves a prior toggled recording")
        _ = engine.handle(.down(isRecording: false), at: 2)
        expect(engine.handle(.finish, at: 2.2) == .finish, "Escape finishes instead of discarding")
        expect(engine.handle(.up, at: 2.3) == nil, "Escape consumes the pending release")
        _ = engine.handle(.down(isRecording: false), at: 3)
        expect(engine.handle(.reset, at: 0) == .finish, "Pausing preserves provisional audio")
        expect(engine.handle(.up, at: 4) == nil, "Pause drops a stale release")
    }

    private static func testEvents() {
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
        hub.send(.keyDown, key: kVK_ANSI_A, flags: .maskSecondaryFn, at: 2.4)
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 2.5)
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 2.6)
        expect(actions == [.start, .cancel], "Other input cancels without rearming a held Globe")

        actions = []
        hub.send(.keyDown, key: kVK_F1, flags: .maskSecondaryFn, at: 3)
        hub.send(.flagsChanged, key: kVK_Shift, flags: .maskAlphaShift, at: 3.1)
        expect(actions.isEmpty, "Function-key fn residue and Caps Lock cannot start dictation")
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 4)
        hub.send(.keyDown, key: kVK_ANSI_A, at: 4.1, isRepeat: true)
        hub.send(.keyDown, key: kVK_ANSI_A, at: 4.2, isSynthetic: true)
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 4.5)
        expect(actions == [.start, .finish], "Repeats and our synthetic typing leave a hold alone")

        for key in [kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter] {
            actions = []
            hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 5)
            hub.send(.keyDown, key: key, at: 5.1)
            hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 5.2)
            expect(actions == [.start, .finish], "Finish keys preserve audio and suppress release toggling")
        }
        actions = []
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 6)
        hub.send(.flagsChanged, key: kVK_Shift, flags: [.maskSecondaryFn, .maskShift], at: 6.4)
        hub.send(.flagsChanged, key: kVK_Shift, flags: .maskSecondaryFn, at: 6.5)
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 6.6)
        expect(actions == [.start, .cancel], "Another modifier cancels the hold")
        actions = []
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 7)
        manager.setEnabled(true, isPaused: true)
        expect(actions == [.start, .finish] && hub.handlers.isEmpty, "Pausing removes its hub consumer")
        hub.send(.flagsChanged, key: kVK_Function, flags: [], at: 7.5)
        expect(actions == [.start, .finish], "An unregistered consumer receives no stale release")
        actions = []
        var temporary: DictationTriggerManager? = DictationTriggerManager(hub: hub, isRecording: { false }) {
            actions.append($0)
        }
        temporary?.setEnabled(true)
        hub.send(.flagsChanged, key: kVK_Function, flags: .maskSecondaryFn, at: 8)
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
        let began = ContinuousClock.now
        do {
            try await DictationCapture.startBounded(
                timeout: .milliseconds(30), start: { release.wait(); return true },
                stop: { finished.withLock { $0 = true } })
            preconditionFailure("Hung start must time out")
        } catch DictationCapture.Failure.coreAudioUnresponsive {
            expect(ContinuousClock.now - began < .seconds(2), "Timeout returns without waiting for a hung driver")
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

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
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
