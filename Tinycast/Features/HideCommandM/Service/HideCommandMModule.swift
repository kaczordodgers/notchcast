import AppKit
import Synchronization

@MainActor
final class HideCommandMModule: NotchcastModule {
    private final class Frontmost: Sendable {
        let pid = Mutex<Int32>(0)
    }

    private let frontmost = Frontmost()
    private let tap: EventTapSubscription
    private var activation: NotificationToken?
    private var generation = UUID()

    init(hub: EventTapHub) { tap = EventTapSubscription(hub: hub) }

    func start() {
        guard !tap.isActive else { return }
        refresh()
        let generation = generation
        let ownPID = ProcessInfo.processInfo.processIdentifier
        tap.startKeyPress(46, skipsSynthetic: true) { [frontmost, weak self] event in
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
            let pid = frontmost.pid.withLock { $0 }
            guard event.flags.intersection(modifiers) == .maskCommand, pid > 0, pid != ownPID else { return false }
            DispatchQueue.main.async { [weak self] in
                self?.hide(pid: pid, generation: generation)
            }
            return true
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
        tap.stop()
        activation = nil
        frontmost.pid.withLock { $0 = 0 }
    }

    private func refresh() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        frontmost.pid.withLock { $0 = pid }
    }

    private func hide(pid: Int32, generation: UUID) {
        guard tap.isActive, self.generation == generation,
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
