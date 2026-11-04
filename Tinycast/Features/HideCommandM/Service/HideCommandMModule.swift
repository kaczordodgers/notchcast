import AppKit
import Synchronization

@MainActor
final class HideCommandMModule: NotchcastModule {
    private struct Session: Sendable {
        var policy = HideCommandMPolicy()
        var pid: Int32 = 0
    }

    private final class SharedSession: Sendable {
        let value = Mutex(Session())
    }

    private let state = SharedSession()
    private let hub: EventTapHub
    private var registration: UUID?
    private var activation: NotificationToken?
    private var generation = UUID()

    init(hub: EventTapHub) { self.hub = hub }

    func start() {
        guard registration == nil else { return }
        refresh()
        let generation = generation
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let mask = EventTapPolicy.mask(for: .keyDown) | EventTapPolicy.mask(for: .keyUp)
        registration = hub.registerSynchronous(mask: mask) { [state, weak self] type, event in
            guard event.getIntegerValueField(.eventSourceUserData) != Paster.tinycastEventTag else { return .pass }
            let result = state.value.withLock { session in
                let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
                let decision = session.policy.consume(
                    keyDown: type == .keyDown,
                    keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                    plainCommand: event.flags.intersection(modifiers) == .maskCommand,
                    isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                    skipped: session.pid <= 0 || session.pid == ownPID)
                return (decision, session.pid)
            }
            if result.0 == .hide {
                DispatchQueue.main.async { [weak self] in
                    self?.hide(pid: result.1, generation: generation)
                }
            }
            return result.0 == .pass ? .pass : .swallow
        }
        let center = NSWorkspace.shared.notificationCenter
        activation = NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }, center: center)
    }

    func stop() {
        generation = UUID()
        if let registration { hub.remove(registration) }
        registration = nil
        activation = nil
        state.value.withLock { $0 = Session() }
    }

    private func refresh() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        state.value.withLock { $0.pid = pid }
        hub.refreshPermission()
    }

    private func hide(pid: Int32, generation: UUID) {
        guard registration != nil, self.generation == generation,
              let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier == pid else { return }
        let isFinder = app.bundleIdentifier == "com.apple.finder"
        let windows = isFinder ? CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] : nil
        let hasWindows = windows?.contains {
            ($0[kCGWindowOwnerPID as String] as? Int32) == pid
                && ($0[kCGWindowLayer as String] as? Int) == 0
        } ?? false
        if HideCommandMPolicy.shouldHide(pid: pid, ownPID: ProcessInfo.processInfo.processIdentifier,
                                        isFinder: isFinder, hasWindows: hasWindows) {
            app.hide()
        } else if isFinder {
            // Replay outside the tap so querying Finder's windows never stalls key delivery.
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 46, keyDown: down) else { continue }
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                event.postToPid(pid)
            }
        }
    }
}
