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
    private let refreshQueue = DispatchQueue(label: "app.notchcast.green-maximize.refresh")
    private var refreshID: UUID?
    private var refreshAgain = false

    nonisolated private static let observerCallback: AXObserverCallback = { _, _, _, context in
        guard let context else { return }
        let owner = Unmanaged<GreenMaximizeModule>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { owner.refresh() }
    }

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
        refreshID = nil
        refreshAgain = false
    }

    private func clearObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = nil
    }

    private func refresh() {
        guard refreshID == nil else { refreshAgain = true; return }
        exclusions = Set(NotchcastPreferences.shared.greenMaximizeExcludedApps
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
            let bundleID = app.bundleIdentifier, !exclusions.contains(bundleID)
        else { shared.value.withLock { $0.snapshot = nil }; return }
        let id = UUID()
        refreshID = id
        let pid = app.processIdentifier
        let observed = observer != nil && observedPID == pid ? window : nil
        let context = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        refreshQueue.async { [weak self] in
            let result = GreenMaximizeRefresh.read(
                pid: pid, observed: observed, callback: Self.observerCallback, context: context)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.refreshID == id else { return }
                self.refreshID = nil
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                    self.publish(result, pid: pid, bundleID: bundleID)
                } else {
                    self.shared.value.withLock { $0.snapshot = nil }
                }
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refresh()
                }
            }
        }
    }

    private func publish(_ result: GreenMaximizeRefresh.Result?, pid: pid_t, bundleID: String) {
        guard let result else { shared.value.withLock { $0.snapshot = nil }; return }
        let focused = result.window
        let changed = window == nil || !CFEqual(window, focused) || observedPID != pid
        if changed {
            clearObserver()
            memory = nil
            generation = UUID()
        }
        window = focused
        if observer == nil {
            if let newObserver = result.observer {
                observer = newObserver
                observedPID = pid
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
            }
        }
        let snapshot = Snapshot(rect: result.rect, pid: pid, bundleID: bundleID,
            date: result.date, generation: generation)
        shared.value.withLock { $0.snapshot = snapshot }
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
