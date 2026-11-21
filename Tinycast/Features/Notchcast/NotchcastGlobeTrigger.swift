import AppKit
import Carbon.HIToolbox

/// Globe-mode Dictation: watches the Globe key only while that mode is on and Dictation enabled.
@MainActor
final class NotchcastGlobeTrigger {
    private weak var core: AppCore?
    private let hub: NotchcastTapHub
    private var isTrusted = false
    private var detector = DictationMode.GlobeDetector()
    private var monitors: [Any] = []
    private var deadlineTask: Task<Void, Never>?
    private var isRunning = true

    init(core: AppCore, hub: NotchcastTapHub) {
        self.core = core
        self.hub = hub
        observe()
    }

    func stop() {
        isRunning = false
        apply(false)
    }

    private func observe() {
        guard isRunning, let core else { return }
        let (wanted, trusted) = withObservationTracking {
            (core.settings.dictationEnabled && core.settings.dictationMode == .globe, hub.isTrusted)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        // A global monitor added before the Accessibility grant never delivers; a new one does.
        if trusted, !isTrusted { apply(false) }
        isTrusted = trusted
        apply(wanted)
    }

    private func apply(_ wanted: Bool) {
        guard wanted != !monitors.isEmpty else { return }
        detector = DictationMode.GlobeDetector()
        deadlineTask?.cancel()
        guard wanted else {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            return
        }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let otherApps = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        // The global monitor never sees this app's own windows, the dictation panel among them.
        let thisApp = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        monitors = [otherApps, thisApp].compactMap { $0 }
    }

    private func handle(_ event: NSEvent) {
        guard let core else { return }
        // A shortcut recorder owns the keyboard while it captures.
        guard core.hotKeys.recordingAction == nil else { return run(detector.interrupted()) }
        switch event.type {
        case .flagsChanged where event.keyCode == UInt16(kVK_Function):
            let flags = event.modifierFlags.intersection([.function, .command, .option, .control, .shift])
            if flags == .function {
                detector.pressed(at: event.timestamp, isRecording: core.dictationCoordinator.isActive)
                scheduleDeadline()
            } else if !flags.contains(.function) {
                run(detector.released(at: event.timestamp))
            } else {
                run(detector.interrupted())
            }
        // macOS follows a bare Globe release with key-down 179; Return and Escape go to the hold.
        case .keyDown where [179, kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape].contains(Int(event.keyCode)):
            break
        default:
            run(detector.interrupted())
        }
    }

    private func scheduleDeadline() {
        deadlineTask?.cancel()
        guard let deadline = detector.deadline else { return }
        deadlineTask = Task { [weak self] in
            // NSEvent timestamps count from boot, as `systemUptime` does.
            try? await Task.sleep(for: .seconds(deadline - ProcessInfo.processInfo.systemUptime))
            guard !Task.isCancelled, let self else { return }
            run(detector.elapsed(at: deadline))
        }
    }

    private func run(_ action: DictationMode.GlobeDetector.Action?) {
        if detector.deadline == nil { deadlineTask?.cancel() }
        guard let action else { return }
        core?.dictationCoordinator.globe(action)
    }
}
