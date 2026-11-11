import AppKit
import Carbon.HIToolbox
import Observation
import Synchronization

@MainActor @Observable
final class QuitProtectionModule: NotchcastModule {
    private(set) var notice: QuitProtectionEngine.Notice?
    private let store: QuitProtectionStore
    private let tap: EventTapSubscription
    private let frontmostTarget: @MainActor () -> QuitProtectionEngine.Target?
    private let state = SharedSession()
    private var timer: Timer?
    private var layoutSource: String?
    private var activation: NotificationToken?
    private var inputSourceChange: NotificationToken?

    private final class SharedSession: Sendable {
        let value = Mutex(Session())
    }

    private struct Session: Sendable {
        var engine = QuitProtectionEngine()
        var target: QuitProtectionEngine.Target?
        var characters: [UInt16: String] = [:]
        var notice: QuitProtectionEngine.Notice?
        var actions: [(QuitProtectionEngine.Target, UInt16)] = []
        var keyCode: UInt16 = 12

        mutating func consume(_ event: QuitProtectionEngine.Event) -> Bool {
            let decision = engine.consume(event, at: ProcessInfo.processInfo.systemUptime, target: target)
            switch decision {
            case .pass: break
            case .swallow(let notice):
                if let notice { self.notice = notice }
            case .quit(let target), .close(let target): actions.append((target, keyCode))
            }
            if engine.deadline == nil { notice = nil }
            return decision != .pass
        }
    }

    init(store: QuitProtectionStore, hub: EventTapHub,
         frontmostTarget: @escaping @MainActor () -> QuitProtectionEngine.Target? = QuitProtectionModule.currentTarget) {
        self.store = store
        tap = EventTapSubscription(hub: hub)
        self.frontmostTarget = frontmostTarget
    }

    func start() {
        NotchcastHost.current.refreshNotchcastCommands()
        guard !tap.isActive else { return }
        refreshLayout()
        refresh()
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap.start(mask: mask, skipsSynthetic: true) { [state, weak self] type, event in
            let verdict: EventTapHub.Verdict = state.value.withLock { session in
                let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
                let key = QuitProtectionEngine.Key(code: code, commandCharacter: session.characters[code])
                var modifiers: QuitProtectionEngine.Modifiers = []
                if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
                if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
                if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
                if event.flags.contains(.maskControl) { modifiers.insert(.control) }
                let input: QuitProtectionEngine.Event
                switch type {
                case .keyDown:
                    session.keyCode = code
                    input = .keyDown(key, modifiers, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
                case .keyUp: input = .keyUp(key)
                case .flagsChanged: input = .modifiersChanged(modifiers)
                default: return .pass
                }
                return session.consume(input) ? .swallow : .pass
            }
            DispatchQueue.main.async { [weak self] in self?.updatePendingPress() }
            return verdict
        }
        let center = NSWorkspace.shared.notificationCenter
        activation = NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }, center: center)
        let inputCenter = DistributedNotificationCenter.default()
        inputSourceChange = NotificationToken(inputCenter.addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLayout() }
        }, center: inputCenter)
        if let id = tap.id { observeConfiguration(id) }
    }

    func stop() {
        NotchcastHost.current.refreshNotchcastCommands()
        tap.stop()
        timer?.invalidate()
        timer = nil
        activation = nil
        inputSourceChange = nil
        layoutSource = nil
        state.value.withLock { $0 = Session() }
        notice = nil
    }

    private static func currentTarget() -> QuitProtectionEngine.Target? {
        let app = NSWorkspace.shared.frontmostApplication
        return app.flatMap { app in
            app.bundleIdentifier.map {
                QuitProtectionEngine.Target(processIdentifier: app.processIdentifier, bundleIdentifier: $0,
                                            name: app.localizedName ?? $0)
            }
        }
    }

    private func observeConfiguration(_ identity: UUID) {
        withObservationTracking {
            state.value.withLock { $0.engine.configuration = store.configuration }
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.tap.id == identity else { return }
                self.observeConfiguration(identity)
                self.updatePendingPress()
            }
        }
    }

    private func refreshLayout() {
        let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let sourceID = source.flatMap { TISGetInputSourceProperty($0, kTISPropertyInputSourceID) }
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
        guard sourceID != layoutSource || state.value.withLock({ $0.characters.isEmpty }) else { return }
        layoutSource = sourceID
        let characters = (0..<128).reduce(into: [UInt16: String]()) { result, code in
            result[UInt16(code)] = ASCIIKeyboardLayout.character(for: code, modifiers: UInt32(cmdKey >> 8))
        }
        state.value.withLock { $0.characters = characters }
    }

    private func refresh() {
        let target = frontmostTarget()
        state.value.withLock { $0.target = target }
        updatePendingPress()
    }

    private func updatePendingPress() {
        guard tap.isActive else { return }
        timer?.invalidate()
        timer = nil
        let result = state.value.withLock { session in
            session.engine.configuration = store.configuration
            _ = session.consume(.tick)
            let actions = session.actions
            session.actions.removeAll()
            return (session.notice, actions, session.engine.deadline)
        }
        notice = result.0
        if let deadline = result.2 {
            let timer = Timer(timeInterval: max(0.001, deadline - ProcessInfo.processInfo.systemUptime),
                              repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        for (destination, code) in result.1 {
            guard destination == frontmostTarget() else { continue }
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
                event.flags = .maskCommand
                event.markSynthetic()
                event.postToPid(destination.processIdentifier)
            }
        }
    }
}
