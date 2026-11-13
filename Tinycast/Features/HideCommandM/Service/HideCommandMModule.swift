import AppKit
import Carbon.HIToolbox
import Synchronization

@MainActor
final class HideCommandMModule: NotchcastModule {
    private final class Frontmost: Sendable {
        let pid = Mutex<Int32>(0)
    }

    private let frontmost = Frontmost()
    private let tap: EventTapSubscription
    private var activation: NotificationToken?
    private var inputSourceChange: NotificationToken?
    private var keyCode: CGKeyCode = 46
    private var generation = UUID()

    init(hub: EventTapHub) { tap = EventTapSubscription(hub: hub) }

    func start() {
        guard !tap.isActive else { return }
        refresh()
        keyCode = Self.layoutKeyCode()
        startTap()
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
            MainActor.assumeIsolated { self?.relayout() }
        }, center: inputCenter)
    }

    /// The key whose Command character is "m" in the current layout: on AZERTY 46 is ⌘, (Settings).
    static func layoutKeyCode() -> CGKeyCode {
        (0..<128).first { ASCIIKeyboardLayout.character(for: $0, modifiers: UInt32(cmdKey >> 8)) == "m" }
            .map(CGKeyCode.init) ?? 46
    }

    private func relayout() {
        let code = Self.layoutKeyCode()
        guard tap.isActive, code != keyCode else { return }
        keyCode = code
        tap.stop()
        startTap()
    }

    private func startTap() {
        let generation = generation
        let ownPID = ProcessInfo.processInfo.processIdentifier
        tap.startKeyPress(Int64(keyCode), skipsSynthetic: true) { [frontmost, weak self] event in
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
            let pid = frontmost.pid.withLock { $0 }
            guard event.flags.intersection(modifiers) == .maskCommand, pid > 0, pid != ownPID else { return false }
            DispatchQueue.main.async { [weak self] in
                self?.hide(pid: pid, generation: generation)
            }
            return true
        }
    }

    func stop() {
        generation = UUID()
        tap.stop()
        activation = nil
        inputSourceChange = nil
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
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
                event.flags = .maskCommand
                event.markSynthetic()
                event.postToPid(pid)
            }
        }
    }
}
