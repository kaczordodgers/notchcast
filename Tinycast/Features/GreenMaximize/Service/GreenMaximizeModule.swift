import AppKit
@preconcurrency import ApplicationServices
import Synchronization

@MainActor
final class GreenMaximizeModule: NotchcastModule {
    private struct Snapshot: Sendable {
        let rect: CGRect
        let pid: pid_t
        let bundleID: String
        let date: TimeInterval
        let generation: UUID
    }

    private struct TapState: Sendable {
        var snapshot: Snapshot?
        var pressed = false
    }

    private final class SharedState: Sendable {
        let value = Mutex(TapState())
    }
    private let shared = SharedState()
    private let hub: EventTapHub
    private var registration: UUID?
    private var activation: NotificationToken?
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var window: AXUIElement?
    private var memory: GreenMaximizeEngine.Memory?
    private var generation = UUID()
    private var timer: Timer?
    private var exclusions: Set<String> = []

    init(hub: EventTapHub) { self.hub = hub }

    func start() {
        guard registration == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        activation = NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }, center: center)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hub.refreshPermission()
                self?.refresh()
            }
        }
        refresh()
        let shared = self.shared
        registration = hub.registerSynchronous(mask:
            EventTapPolicy.mask(for: .leftMouseDown) | EventTapPolicy.mask(for: .leftMouseUp)
        ) { [weak self] type, event in
            let result: (Bool, Snapshot?) = shared.value.withLock { value in
                if type == .leftMouseUp {
                    let swallowed = value.pressed
                    value.pressed = false
                    return (swallowed, nil)
                }
                guard let snapshot = value.snapshot,
                    GreenMaximizeClick.intercept(
                        point: event.location, rect: snapshot.rect,
                        age: ProcessInfo.processInfo.systemUptime - snapshot.date,
                        option: event.flags.contains(.maskAlternate),
                        bundleID: snapshot.bundleID, exclusions: [])
                else { return (false, nil) }
                value.pressed = true
                return (true, snapshot)
            }
            if let snapshot = result.1 {
                DispatchQueue.main.async { [weak self] in self?.maximize(snapshot) }
            }
            return result.0 ? .swallow : .pass
        }
    }

    func stop() {
        shared.value.withLock { $0 = TapState() }
        if let registration { hub.remove(registration) }
        registration = nil
        activation = nil
        timer?.invalidate()
        timer = nil
        clearObserver()
        window = nil
        memory = nil
        generation = UUID()
    }

    private func clearObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = nil
    }

    private func refresh() {
        var snapshot: Snapshot?
        defer { shared.value.withLock { $0.snapshot = snapshot } }
        exclusions = Set(NotchcastPreferences.shared.greenMaximizeExcludedApps
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
            let bundleID = app.bundleIdentifier, !exclusions.contains(bundleID)
        else { return }
        let application = AXWindowAccess.application(for: app.processIdentifier, timeout: 0.1)
        guard let focused = AXWindowAccess.element(application, kAXFocusedWindowAttribute),
            AXWindowAccess.isEligible(focused), !AXWindowAccess.isFullScreen(focused),
            AXWindowAccess.isSettable(kAXSizeAttribute, on: focused),
            let button = AXWindowAccess.element(focused, kAXZoomButtonAttribute)
                ?? AXWindowAccess.element(focused, "AXFullScreenButton"),
            AXWindowAccess.bool(button, kAXEnabledAttribute) != false,
            let rect = AXWindowAccess.frame(of: button)
        else { return }
        let changed = window == nil || !CFEqual(window, focused) || observedPID != app.processIdentifier
        if changed {
            clearObserver()
            memory = nil
            generation = UUID()
        }
        window = focused
        if observer == nil {
            var newObserver: AXObserver?
            if AXObserverCreate(app.processIdentifier, { _, _, _, context in
                guard let context else { return }
                let owner = Unmanaged<GreenMaximizeModule>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { owner.refresh() }
            }, &newObserver) == .success, let newObserver {
                observer = newObserver
                observedPID = app.processIdentifier
                let context = Unmanaged.passUnretained(self).toOpaque()
                AXObserverAddNotification(newObserver, application,
                    kAXFocusedWindowChangedNotification as CFString, context)
                for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                    AXObserverAddNotification(newObserver, focused, name as CFString, context)
                }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
            }
        }
        snapshot = Snapshot(rect: rect, pid: app.processIdentifier, bundleID: bundleID,
            date: ProcessInfo.processInfo.systemUptime, generation: generation)
    }

    private func maximize(_ snapshot: Snapshot) {
        guard registration != nil, snapshot.generation == generation,
            NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid,
            let window, let focused = AXWindowAccess.element(
                AXWindowAccess.application(for: snapshot.pid, timeout: 0.1), kAXFocusedWindowAttribute),
            CFEqual(window, focused), !AXWindowAccess.isFullScreen(window),
            let current = AXWindowAccess.frame(of: window)
        else { return }
        let screens = NSScreen.screens
        let geometry = AXGeometry(screens: screens)
        guard let screen = screens.max(by: {
            geometry.flip($0.frame).intersection(current).area
                < geometry.flip($1.frame).intersection(current).area
        }), let target = GreenMaximizeEngine.target(
            current: current, visible: geometry.flip(screen.visibleFrame), memory: memory)
        else { return }
        let restore = AXWindowAccess.suppressEnhancedUserInterface(
            on: AXWindowAccess.application(for: snapshot.pid, timeout: 0.1))
        defer { restore(); refresh() }
        guard let applied = AXWindowAccess.write(target, anchor: .centered, to: window,
            current: current, canResize: true, canvas: nil) else { return }
        memory = GreenMaximizeEngine.memory(original: current, requested: target, applied: applied)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
