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
        var snapshots: [Snapshot] = []
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
    private var window: AXUIElement?
    private var memory: GreenMaximizeEngine.Memory?
    private var generation = UUID()
    private var timer: Timer?
    private var exclusions: Set<String> = []
    private let refreshQueue = DispatchQueue(label: "app.notchcast.green-maximize.refresh")
    private var refreshID: UUID?
    private var refreshAgain = false

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
                guard let snapshot = GreenMaximizeClick.target(
                    point: event.location, candidates: value.snapshots, rect: {
                        $0.rect.contains(event.location)
                            && GreenMaximizeRefresh.verifies($0.target, point: event.location) ? $0.rect : .null
                    }),
                    GreenMaximizeClick.intercept(
                        point: event.location, rect: snapshot.rect,
                        age: ProcessInfo.processInfo.systemUptime - snapshot.date,
                        option: event.flags.contains(.maskAlternate),
                        bundleID: snapshot.bundleID, exclusions: [],
                        verified: GreenMaximizeRefresh.verifies(snapshot.target, point: event.location))
                else { return (false, nil) }
                value.pressed = true
                return (true, snapshot)
            }
            if let snapshot = result.1 {
                DispatchQueue.main.async { [weak self] in self?.maximize(snapshot) }
            } else if type == .leftMouseDown {
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
            return result.0 ? .swallow : .pass
        }
    }

    func stop() {
        shared.value.withLock { $0 = TapState() }
        if let registration { hub.remove(registration) }
        registration = nil
        activation = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        timer?.invalidate()
        timer = nil
        window = nil
        memory = nil
        generation = UUID()
        refreshID = nil
        refreshAgain = false
    }

    private func refresh() {
        observeFrontmost()
        guard refreshID == nil else { refreshAgain = true; return }
        exclusions = Set(NotchcastPreferences.shared.greenMaximizeExcludedApps
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard AXIsProcessTrusted()
        else { shared.value.withLock { $0.snapshots = [] }; return }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] ?? []
        let visiblePIDs = Set(windows.compactMap { info -> pid_t? in
            guard info[kCGWindowLayer as String] as? Int == 0 else { return nil }
            return info[kCGWindowOwnerPID as String] as? pid_t
        })
        let orderedPIDs = windows.compactMap { $0[kCGWindowOwnerPID as String] as? pid_t }
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String)? in
            guard visiblePIDs.contains(app.processIdentifier), app.activationPolicy != .prohibited,
                let bundleID = app.bundleIdentifier, !exclusions.contains(bundleID) else { return nil }
            return (app.processIdentifier, bundleID)
        }.sorted { (orderedPIDs.firstIndex(of: $0.0) ?? .max) < (orderedPIDs.firstIndex(of: $1.0) ?? .max) }
        let id = UUID()
        refreshID = id
        let generation = self.generation
        refreshQueue.async { [weak self] in
            let snapshots = apps.flatMap { pid, bundleID in
                GreenMaximizeRefresh.readAll(pid: pid).map { result in
                    Snapshot(rect: result.rect, pid: pid, bundleID: bundleID,
                        date: result.date, generation: generation, target: result)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.refreshID == id else { return }
                self.refreshID = nil
                self.shared.value.withLock { $0.snapshots = snapshots }
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refresh()
                }
            }
        }
    }

    private func observeFrontmost() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<GreenMaximizeModule>.fromOpaque(context).takeUnretainedValue()
                owner.shared.value.withLock { $0.snapshots = [] }
                owner.refresh()
            }
        }, &created) == .success, let created else { return }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.01)
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, application, kAXFocusedWindowChangedNotification as CFString, context)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        for window in value as? [AXUIElement] ?? [] {
            for notification in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                AXObserverAddNotification(created, window, notification as CFString, context)
            }
        }
        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    private func maximize(_ snapshot: Snapshot) {
        let clicked = snapshot.target.window
        guard registration != nil, snapshot.generation == generation,
            !AXWindowAccess.isFullScreen(clicked),
            let current = AXWindowAccess.frame(of: clicked)
        else { return }
        if window == nil || !CFEqual(window, clicked) { memory = nil }
        window = clicked
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
        guard let applied = AXWindowAccess.write(target, anchor: .centered, to: clicked,
            current: current, canResize: true, canvas: nil) else { return }
        memory = GreenMaximizeEngine.memory(original: current, requested: target, applied: applied)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
