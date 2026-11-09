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
        let target: GreenMaximizeRefresh.Result
    }

    private struct TapState: Sendable {
        var snapshot: Snapshot?
        var pointerSnapshot: Snapshot?
        var pointerGate = GreenMaximizeClick.PointerGate()
        var exclusions: Set<String> = []
        var click = GreenMaximizeClick.Session()
    }

    private final class SharedState: Sendable {
        let value = Mutex(TapState())
    }
    private let shared = SharedState()
    private let hub: EventTapHub
    private let tap: EventTapSubscription
    private var activation: NotificationToken?
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var window: AXUIElement?
    private var memory: GreenMaximizeEngine.Memory?
    private var generation = UUID()
    private var timer: Timer?
    private var exclusions: Set<String> = []
    private let refreshQueue = DispatchQueue(label: "app.notchcast.green-maximize.refresh")
    private let pointerQueue = DispatchQueue(label: "app.notchcast.green-maximize.pointer")
    private var refreshID: UUID?
    private var refreshAgain = false
    private var pointerID: UUID?
    private var pointerPoint: CGPoint?
    private var memoryWindow: AXUIElement?

    nonisolated private static let observerCallback: AXObserverCallback = { _, _, _, context in
        guard let context else { return }
        let owner = Unmanaged<GreenMaximizeModule>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { owner.refresh() }
    }

    init(hub: EventTapHub) {
        self.hub = hub
        tap = EventTapSubscription(hub: hub)
    }

    func start() {
        guard !tap.isActive else { return }
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
        tap.start(mask:
            EventTapPolicy.mask(for: .leftMouseDown) | EventTapPolicy.mask(for: .leftMouseUp)
                | EventTapPolicy.mask(for: .mouseMoved) | EventTapPolicy.mask(for: .leftMouseDragged)
        ) { [weak self] type, event in
            if type == .mouseMoved {
                let point = event.location
                let changed = shared.value.withLock { value in
                    let changed = value.pointerGate.moved(to: point)
                    if changed { value.pointerSnapshot = nil }
                    return changed
                }
                if changed {
                    DispatchQueue.main.async { [weak self] in self?.refreshPointer(point) }
                }
            }
            let result: (Bool, Snapshot?) = shared.value.withLock { value in
                let kind: GreenMaximizeClick.Event
                switch type {
                case .leftMouseDown: kind = .down
                case .leftMouseUp: kind = .up
                case .leftMouseDragged: kind = .drag
                default: kind = .move
                }
                let snapshot = GreenMaximizeClick.target(
                    pointer: value.pointerSnapshot, frontmost: value.snapshot
                ) { snapshot in
                    GreenMaximizeClick.intercept(
                        point: event.location, rect: snapshot.rect,
                        age: ProcessInfo.processInfo.systemUptime - snapshot.date,
                        option: event.flags.contains(.maskAlternate),
                        bundleID: snapshot.bundleID, exclusions: value.exclusions)
                }
                let decision = value.click.decide(kind, hit: snapshot != nil)
                return (decision.swallow, decision.maximize ? snapshot : nil)
            }
            if let snapshot = result.1 {
                DispatchQueue.main.async { [weak self] in self?.maximize(snapshot) }
            }
            return result.0 ? .swallow : .pass
        }
    }

    func stop() {
        shared.value.withLock { $0 = TapState() }
        tap.stop()
        activation = nil
        timer?.invalidate()
        timer = nil
        clearObserver()
        window = nil
        memory = nil
        generation = UUID()
        refreshID = nil
        refreshAgain = false
        pointerID = nil
        pointerPoint = nil
        memoryWindow = nil
    }

    private func clearObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = nil
    }

    private func refresh() {
        refreshPointerZones()
        let mouse = NSEvent.mouseLocation
        refreshPointer(CGPoint(x: mouse.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - mouse.y))
        guard refreshID == nil else { refreshAgain = true; return }
        exclusions = Set(NotchcastPreferences.shared.greenMaximizeExcludedApps
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        shared.value.withLock { $0.exclusions = exclusions }
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
            date: result.date, generation: generation, target: result)
        shared.value.withLock { $0.snapshot = snapshot }
    }

    private func maximize(_ snapshot: Snapshot) {
        guard tap.isActive, snapshot.generation == generation,
            ProcessInfo.processInfo.systemUptime - snapshot.date < 2,
            !exclusions.contains(snapshot.bundleID)
        else { return }
        let window = snapshot.target.window
        guard !AXWindowAccess.isFullScreen(window),
            let current = AXWindowAccess.frame(of: window)
        else { return }
        if memoryWindow == nil || !CFEqual(memoryWindow, window) { memory = nil }
        memoryWindow = window
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

    private func refreshPointer(_ point: CGPoint) {
        guard tap.isActive else { return }
        pointerPoint = point
        refreshPointerZones()
        let inside = shared.value.withLock { value in
            value.pointerGate.zones.contains { $0.contains(point) }
        }
        guard inside else {
            shared.value.withLock { $0.pointerSnapshot = nil }
            return
        }
        guard pointerID == nil else { return }
        let id = UUID()
        pointerID = id
        pointerQueue.async { [weak self] in
            let result = GreenMaximizeRefresh.underPointer(point)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pointerID == id else { return }
                self.pointerID = nil
                var snapshot: Snapshot?
                let stillInside = self.shared.value.withLock { $0.pointerGate.zone != nil }
                if stillInside, self.pointerPoint == point, let (pid, result) = result,
                    let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                    !self.exclusions.contains(bundleID) {
                    snapshot = Snapshot(rect: result.rect, pid: pid, bundleID: bundleID,
                        date: result.date, generation: self.generation, target: result)
                }
                self.shared.value.withLock { $0.pointerSnapshot = snapshot }
                if let latest = self.pointerPoint, latest != point { self.refreshPointer(latest) }
            }
        }
    }

    private func refreshPointerZones() {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] ?? []
        let zones = windows.compactMap { info -> CGRect? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return GreenMaximizeClick.PointerGate.zone(bounds: rect, layer: layer)
        }
        shared.value.withLock { $0.pointerGate.zones = zones }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
