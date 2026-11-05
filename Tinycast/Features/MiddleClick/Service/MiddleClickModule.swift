import AppKit
import Synchronization

@MainActor
final class MiddleClickModule: NotchcastModule {
    private let hub: EventTapHub
    private var source: MiddleClickTouchSource?
    private var registration: UUID?
    private var permissionTimer: Timer?
    private var wakeObserver: NotificationToken?
    private var nextSourceAttempt: TimeInterval = 0
    private let state = State()

    init(hub: EventTapHub) { self.hub = hub }

    func start() {
        refresh()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        let center = NSWorkspace.shared.notificationCenter
        // Sleep invalidates the multitouch devices, and the device list is only read at start.
        wakeObserver = NotificationToken(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restartInput() }
        }, center: center)
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        wakeObserver = nil
        stopInput()
    }

    private func restartInput() {
        guard wakeObserver != nil else { return }
        stopInput()
        nextSourceAttempt = 0
        refresh()
    }

    private func stopInput() {
        state.reset()
        source?.stop()
        source = nil
        if let registration { hub.remove(registration) }
        registration = nil
    }

    private func refresh() {
        state.refreshDragPreference()
        guard AXIsProcessTrusted() else { stopInput(); return }
        guard registration == nil else { hub.refreshPermission(); return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextSourceAttempt else { return }
        nextSourceAttempt = now + 60
        guard let source = MiddleClickTouchSource() else { return }
        let state = state
        state.activate()
        guard source.start({ device, points, time in
            state.frame(device: device, points: points, time: time)
        }) else { state.reset(); return }
        self.source = source
        let mask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        registration = hub.registerSynchronous(mask: mask) { type, event in
            state.handle(type, event: event)
        }
    }

    // Touch callbacks and the hub run on different threads; one lock serializes decisions and posts.
    private final class State: Sendable {
        private struct Storage {
            var active = false
            var dragEnabled = false
            var filter = MiddleClickFilter()
            let touches = ThreeFingerState(clock: { ProcessInfo.processInfo.systemUptime })
        }
        private let storage = Mutex(Storage())

        func activate() { storage.withLock { $0.active = true } }

        func refreshDragPreference() {
            let enabled = Self.dragEnabled
            storage.withLock { $0.dragEnabled = enabled }
        }

        func reset() {
            storage.withLock {
                $0.active = false
                if $0.filter.reset() { Self.post(.otherMouseUp) }
                $0.touches.reset()
            }
        }

        func frame(device: Int, points: [TouchPoint], time: Double) {
            storage.withLock {
                guard $0.active else { return }
                guard $0.touches.frame(device: device, touches: points, at: time), !$0.dragEnabled,
                      MiddleClickGuards.tapAllowed(secondsSinceKeyDown:
                        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown))
                else { return }
                Self.post(.otherMouseDown)
                Self.post(.otherMouseUp)
                $0.touches.markMiddleClick()
            }
        }

        func handle(_ type: CGEventType, event: CGEvent) -> EventTapHub.Verdict {
            storage.withLock {
                guard $0.active,
                      event.getIntegerValueField(.eventSourceUserData) != Paster.tinycastEventTag
                else { return .pass }
                let button: MiddleClickFilter.ButtonEvent
                switch type {
                case .leftMouseDown: button = .down
                case .leftMouseDragged: button = .drag
                case .leftMouseUp: button = .up
                default: return .pass
                }
                let press = button == .down ? $0.touches.press() : .plain
                let decision = $0.filter.decide(button, press: $0.dragEnabled ? .plain : press)
                switch decision {
                case .pass: return .pass
                case .swallow: return .swallow
                case .down, .drag: break
                case .up: $0.touches.markMiddleClick()
                }
                MiddleClickFilter.rewrite(event, for: decision)
                return .pass
            }
        }

        private static var dragEnabled: Bool {
            ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
                .contains { domain in
                    (CFPreferencesCopyAppValue("TrackpadThreeFingerDrag" as CFString,
                                               domain as CFString) as? NSNumber)?.boolValue == true
                }
        }

        // Posted at the HID tap so WindowServer routes it to the window under the pointer.
        private static func post(_ type: CGEventType) {
            guard let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                                      mouseType: type,
                                      mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero,
                                      mouseButton: .center) else { return }
            event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
        }
    }
}
