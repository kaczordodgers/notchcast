import AppKit
import Carbon.HIToolbox

@MainActor
final class DictationTriggerManager {
    private let hub: EventTapHub
    private let isRecording: () -> Bool
    private let perform: (DictationTriggerEngine.Action) -> Void
    private var registration: UUID?
    private var engine = DictationTriggerEngine()
    private var globeDown = false
    private var confirmation: Task<Void, Never>?

    init(
        hub: EventTapHub, isRecording: @escaping () -> Bool,
        perform: @escaping (DictationTriggerEngine.Action) -> Void
    ) {
        self.hub = hub
        self.isRecording = isRecording
        self.perform = perform
    }

    isolated deinit {
        stop()
    }

    func setEnabled(_ isEnabled: Bool, isPaused: Bool = false) {
        guard isEnabled, !isPaused else { stop(); return }
        guard registration == nil else { return }
        let types: [CGEventType] = [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | EventTapPolicy.mask(for: $1) }
        registration = hub.register(mask: mask) { [weak self] in self?.receive($0) }
    }

    func stop() {
        confirmation?.cancel()
        confirmation = nil
        if let registration { hub.remove(registration) }
        registration = nil
        globeDown = false
        if let action = engine.handle(.reset, at: 0) { perform(action) }
    }

    private func receive(_ event: EventTapHub.Event) {
        guard registration != nil, !event.isSynthetic else { return }
        let now = Double(event.timestamp) / 1_000_000_000
        let input: DictationTriggerEngine.Input
        if event.type == .flagsChanged {
            let wasDown = globeDown
            if event.keyCode == kVK_Function { globeDown = event.flags.contains(.maskSecondaryFn) }
            let otherModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
            if !event.flags.isDisjoint(with: otherModifiers) {
                input = .otherInput
            } else if event.keyCode == kVK_Function {
                guard wasDown != globeDown else { return }
                input = globeDown ? .down(isRecording: isRecording()) : .up
            } else {
                return
            }
        } else if event.type == .keyDown {
            // Bare Globe emits key 179, and function keys carry fn without a Globe press.
            guard event.keyCode != 179, !event.isRepeat else { return }
            if event.keyCode == kVK_Escape {
                guard globeDown else { return }
                input = .cancel
            } else if event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter {
                guard globeDown else { return }
                input = .finish
            } else {
                input = .otherInput
            }
        } else {
            input = .otherInput
        }
        confirmation?.cancel()
        confirmation = nil
        if let action = engine.handle(input, at: now) { perform(action) }
        if case .down = input {
            confirmation = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(DictationTriggerEngine.holdThreshold))
                } catch { return }
                guard let self else { return }
                if let action = self.engine.handle(.confirm, at: now + DictationTriggerEngine.holdThreshold) {
                    self.perform(action)
                }
                self.confirmation = nil
            }
        }
    }
}
