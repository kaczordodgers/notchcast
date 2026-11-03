import AppKit
import Carbon.HIToolbox
import Observation
import Synchronization

@MainActor @Observable
final class QuitProtectionModule: NotchcastModule {
    private(set) var notice: QuitProtectionEngine.Notice?
    private let store: QuitProtectionStore
    private let hub: EventTapHub
    private let frontmostTarget: @MainActor () -> QuitProtectionEngine.Target?
    private let state = SharedSession()
    private var registration: UUID?
    private var timer: Timer?
    private var layoutSource: String?
    private var activation: NotificationToken?
    private var trusted = false

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
        self.hub = hub
        self.frontmostTarget = frontmostTarget
    }

    func start() {
        guard registration == nil else { return }
        refresh()
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        registration = hub.registerSynchronous(mask: mask) { [state] type, event in
            guard event.getIntegerValueField(.eventSourceUserData) != Paster.tinycastEventTag else { return .pass }
            return state.value.withLock { session in
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
        }
        let center = NSWorkspace.shared.notificationCenter
        activation = NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }, center: center)
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        if let registration { hub.remove(registration) }
        registration = nil
        timer?.invalidate()
        timer = nil
        activation = nil
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

    private func refresh() {
        let currentTrust = AXIsProcessTrusted()
        if currentTrust != trusted {
            trusted = currentTrust
            hub.refreshPermission()
        }
        let target = frontmostTarget()
        let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let sourceID = source.flatMap { TISGetInputSourceProperty($0, kTISPropertyInputSourceID) }
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
        let characters = sourceID == layoutSource ? nil : (0..<128).reduce(into: [UInt16: String]()) { result, code in
            result[UInt16(code)] = ASCIIKeyboardLayout.character(for: code, modifiers: UInt32(cmdKey >> 8))
        }
        layoutSource = sourceID
        let result = state.value.withLock { session in
            session.engine.configuration = store.configuration
            session.target = target
            if let characters { session.characters = characters }
            _ = session.consume(.tick)
            let actions = session.actions
            session.actions.removeAll()
            return (session.notice, actions)
        }
        notice = result.0
        for (destination, code) in result.1 {
            guard destination == target else { continue }
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                event.postToPid(destination.processIdentifier)
            }
        }
    }
}
