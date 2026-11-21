import AppKit
// `@preconcurrency` downgrades AX diagnostics: the attribute keys are constant C globals.
@preconcurrency import ApplicationServices
import Observation

@MainActor
final class IslandCoordinator: NSObject {
    private unowned let core: AppCore
    private var backdrops: [CGDirectDisplayID: IslandController] = [:]
    private(set) var active: IslandController?
    /// Windows shown again after `.none`: AppKit then drops `.none`, though `.readOnly` still lands.
    private var reshown = Set<ObjectIdentifier>()
    private weak var panel: PalettePanel?
    private var spaceCheck: Task<Void, Never>?
    private var started = false
    private(set) lazy var overlays = IslandOverlayController(island: self)
    var paletteLevel: NSWindow.Level { IslandVerification.stock ? .palette : IslandController.paletteLevel }
    private(set) lazy var pillMenu = IslandPillMenu(core: core)
    private(set) lazy var glance = IslandCalendarGlance(core: core) { [weak self] in self?.showGlance($0) }
    private var restingGlance: IslandGlance?
    private(set) lazy var update = IslandUpdateActivity(core: core)
    private(set) lazy var hover = IslandHoverTracker(core: core)
    private(set) lazy var looks = IslandLookStore(defaults: UserDefaults(
        suiteName: NotchcastPreferences.suiteName(bundleID: Bundle.main.bundleIdentifier ?? "Notchcast")) ?? .standard)

    init(core: AppCore) { self.core = core }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(modalChanged), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowShown),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: name,
                                                              object: nil)
        }
        rebuild()
        observeVisibility()
        observeCaptureSharing()
        observeOutline()
        observePosition()
        observeLooks()
        glance.start()
        update.start()
        hover.start()
    }

    var resting: IslandController? { backdrops.values.first { $0.showsRest } }

    func controller(on display: UInt32) -> IslandController? { backdrops[display] }

    private func showGlance(_ next: IslandGlance?) {
        restingGlance = next
        for controller in backdrops.values { controller.glance = controller.showsRest ? next : nil }
        syncExpansion()
    }

    private var screens: [NSScreen] {
        #if DEBUG
        if IslandVerification.enabled {
            return IslandVerification.screens ?? IslandVerification.testScreen.map { [$0] } ?? []
        }
        #endif
        return NSScreen.screens
    }

    @objc private func rebuild() {
        let presenter = core.islandPresenter as? IslandPresenter
        let available = screens
        let connected = Set(available.map(\.islandDisplayID))
        for id in backdrops.keys where !connected.contains(id) { dropBackdrop(id) }
        let main = available.first(where: { $0.islandDisplayID == NSScreen.primary?.islandDisplayID }) ?? available.first
        for screen in available {
            let backdrop = backdrops[screen.islandDisplayID] ?? IslandController()
            backdrop.showsRest = screen.islandDisplayID == main?.islandDisplayID
            backdrop.outlineWhenOpen = core.settings.islandOutlineWhenOpen
            backdrop.canOpen = { [weak self, weak backdrop] in
                backdrop?.showsRest == true && self?.panel?.isVisible != true
            }
            // The launcher has its hotkey; a click acts on what the island shows, else opens and pins it.
            backdrop.onOpen = { [weak self, weak backdrop] in
                guard backdrop?.showsRest == true else { return }
                if let tap = presenter?.tap { return tap() }
                self?.hover.pin()
            }
            backdrop.onSettle = { [weak self] in self?.hover.refresh() }
            backdrop.canvas.onPointer = { [weak self] in self?.hover.refresh() }
            backdrop.onMenu = { [weak self] pill, window in self?.pillMenu.toggle(below: pill, in: window) }
            backdrop.glance = backdrop.showsRest ? restingGlance : nil
            presenter?.restore(backdrop, resting: backdrop.showsRest)
            backdrop.position = core.settings.islandPosition
            backdrop.configure(screen)
            backdrops[screen.islandDisplayID] = backdrop
        }
        applyLooks()
        shareCaptures()
        overlays.reposition()
        presenter?.restingChanged()
        if restingGlance != nil { syncExpansion() }
        spaceChanged()
        hover.refresh()
    }

    private func dropBackdrop(_ id: CGDirectDisplayID) {
        guard let controller = backdrops[id] else { return }
        if active === controller { controller.detach(); active = nil }
        (core.islandPresenter as? IslandPresenter)?.restore(controller, resting: false)
        reshown.remove(ObjectIdentifier(controller))
        backdrops[id] = nil
    }

    var captureSharing: NSWindow.SharingType { core.settings.islandShowsInCaptures ? .readOnly : .none }

    /// Catches a window created after the last sweep the moment it first shows.
    @objc private func windowShown(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.occlusionState.contains(.visible) else { return }
        window.sharingType = IslandCaptureSharing.sharing(for: window, captures: captureSharing)
    }

    /// Every untitled Notchcast window follows "Show in screenshots and videos" live.
    func applyCaptureSharing() {
        let stuck = shareCaptures()
        // Closing the menu re-enters here; closing the launcher does through `observeVisibility`.
        if pillMenu.leaksCapture || (!stuck.isEmpty && pillMenu.isObservingResign) { return pillMenu.hide() }
        guard !stuck.isEmpty else { return }
        if core.palette.isVisible { return core.paletteCoordinator.hidePalette(restoreFocus: false) }
        for id in stuck { dropBackdrop(id) }
        rebuild()
    }

    /// Returns the displays whose window can't be hidden in place and must be replaced.
    @discardableResult private func shareCaptures() -> [CGDirectDisplayID] {
        let sharing = captureSharing
        pillMenu.sharingType = sharing
        for controller in backdrops.values {
            if sharing == .readOnly, controller.sharingType == .none { reshown.insert(ObjectIdentifier(controller)) }
            controller.sharingType = sharing
        }
        for window in NSApp.windows where !(window is IslandBackdrop) {
            window.sharingType = IslandCaptureSharing.sharing(for: window, captures: sharing)
        }
        guard sharing == .none else { return [] }
        return backdrops.filter { reshown.contains(ObjectIdentifier($0.value)) }.map(\.key)
    }

    @objc func spaceChanged() {
        spaceCheck?.cancel()
        let candidates = AXIsProcessTrusted() ? Self.fullScreenCandidates(on: screens) : []
        spaceCheck = Task { [weak self] in
            let full = await Self.confirmFullScreen(candidates)
            guard !Task.isCancelled, let self else { return }
            for (id, backdrop) in backdrops { backdrop.onFullScreenSpace = full.contains(id) }
            for screen in screens { backdrops[screen.islandDisplayID]?.refreshMenuBar(screen) }
            hover.refresh()
        }
    }

    /// Bounds alone match a zoomed window too, so display-wide windows are only leads.
    private static func fullScreenCandidates(on screens: [NSScreen])
        -> [(display: CGDirectDisplayID, pid: pid_t, bounds: CGRect)] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return screens.flatMap { screen in
            let display = CGDisplayBounds(screen.islandDisplayID)
            return windows.compactMap { info -> (display: CGDirectDisplayID, pid: pid_t, bounds: CGRect)? in
                guard info[kCGWindowLayer as String] as? Int == 0,
                      let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                      let rect = info[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: rect),
                      abs(bounds.minX - display.minX) < 1, abs(bounds.width - display.width) < 1,
                      abs(bounds.maxY - display.maxY) < 1 else { return nil }
                return (screen.islandDisplayID, pid, bounds)
            }
        }
    }

    /// Off the main actor: a hung app would otherwise freeze the island for each timed-out read.
    @concurrent
    nonisolated private static func confirmFullScreen(
        _ candidates: [(display: CGDirectDisplayID, pid: pid_t, bounds: CGRect)]) async -> Set<CGDirectDisplayID> {
        let timeout: Float = 0.25
        var fullFrames: [pid_t: [CGRect]] = [:]
        for pid in Set(candidates.map(\.pid)) {
            guard !Task.isCancelled else { return [] }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, timeout)
            var list: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list) == .success,
                  let windows = list as? [AXUIElement] else { continue }
            fullFrames[pid] = windows.compactMap { window in
                guard !Task.isCancelled else { return nil }
                AXUIElementSetMessagingTimeout(window, timeout)
                var full: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &full) == .success,
                      full as? Bool == true else { return nil }
                return frame(of: window)
            }
        }
        return Set(candidates.filter { candidate in
            fullFrames[candidate.pid, default: []].contains { matches($0, candidate.bounds) }
        }.map(\.display))
    }

    nonisolated private static func frame(of window: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        var value: CFTypeRef?
        guard !Task.isCancelled,
              AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let position = value, CFGetTypeID(position) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin), !Task.isCancelled,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let extent = value, CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(extent, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The top edge moves with the menu bar's reveal strip, so only the other three edges must agree.
    nonisolated private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.width - b.width) < 1 && abs(a.maxY - b.maxY) < 1
    }

    /// Also after a rebuild, so a new resting pill picks up an expansion already showing.
    private func syncExpansion() {
        (core.islandPresenter as? IslandPresenter)?.meetingChanged(glance.occurrence)
    }

    func overlayContext(screen preferred: NSScreen?) -> (NSScreen, IslandController, CGRect?)? {
        if !started { start() }
        let available = screens
        let id = IslandScreenSelection.choose(available: available.map(\.islandDisplayID),
            preferred: preferred?.islandDisplayID, retained: panel?.isVisible == true ? panel?.screen?.islandDisplayID : nil)
        guard let screen = available.first(where: { $0.islandDisplayID == id }),
              let controller = backdrops[screen.islandDisplayID] else { return nil }
        let palette = panel.flatMap { $0.isVisible && $0.screen?.islandDisplayID == id ? $0.frame : nil }
        return (screen, controller, palette)
    }

    func anchor(_ window: NSPanel, width: CGFloat, collapsed: Bool) -> CGPoint? {
        guard let panel = window as? PalettePanel else { return nil }
        panel.sharingType = captureSharing
        let outset = IslandPaletteSurface.renderingOutset(collapsed: collapsed, stock: IslandVerification.stock)
        #if DEBUG
        if IslandVerification.stock, let screen = screens.first {
            return CGPoint(x: screen.frame.midX - width / 2, y: screen.frame.maxY - outset)
        }
        #endif
        if !started { start() }
        let available = screens
        let pointer = NSEvent.mouseLocation
        let retained = panel.isVisible ? available.first { backdrops[$0.islandDisplayID] === active } : nil
        let id = IslandScreenSelection.choose(available: available.map(\.islandDisplayID),
            preferred: retained?.islandDisplayID,
            retained: available.first(where: { $0.frame.contains(pointer) })?.islandDisplayID)
        guard let screen = available.first(where: { $0.islandDisplayID == id }),
              let backdrop = backdrops[screen.islandDisplayID] else { return nil }
        if active !== backdrop {
            active?.detach()
            active = backdrop
        }
        self.panel = panel
        backdrop.attach(panel, screen: screen)
        applyLooks()
        guard let top = backdrop.openingTop, let x = backdrop.openingX(width: width) else { return nil }
        return CGPoint(x: x, y: top - outset)
    }

    var questionScreen: NSScreen? {
        #if DEBUG
        if IslandVerification.enabled { return screens.first }
        #endif
        return panel?.isVisible == true ? panel?.screen : NSScreen.underCursor
    }

    @objc private func modalChanged() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(modalEnded), object: nil)
        if NSApp.modalWindow != nil {
            // Default-mode work resumes after the nested modal loop ends.
            perform(#selector(modalEnded), with: nil, afterDelay: 0, inModes: [.default])
        } else {
            modalEnded()
        }
    }

    @objc private func modalEnded() {
        if NSApp.modalWindow == nil, let panel, panel.isVisible, panel.level < paletteLevel {
            panel.level = paletteLevel
        }
        for controller in backdrops.values { controller.frameChanged() }
        hover.refresh()
    }

    private func observeCaptureSharing() {
        withObservationTracking {
            _ = core.settings.islandShowsInCaptures
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeCaptureSharing()
                self.applyCaptureSharing()
            }
        }
    }

    private func observeOutline() {
        withObservationTracking {
            _ = core.settings.islandOutlineWhenOpen
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeOutline()
                for controller in self.backdrops.values { controller.outlineWhenOpen = self.core.settings.islandOutlineWhenOpen }
            }
        }
    }

    private func observePosition() {
        withObservationTracking {
            _ = core.settings.islandPosition
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observePosition()
                self.rebuild()
            }
        }
    }

    /// The look an AppKit surface on `screen` takes.
    func look(for screen: NSScreen) -> IslandLook {
        looks.look(uuid: screen.islandDisplayUUID, hasNotch: IslandLayout.notch(on: screen) != .zero)
    }

    /// Whether a question or report on `screen` sits on Frosted glass; nil is the question's.
    func frosted(on screen: NSScreen?) -> Bool {
        (screen ?? questionScreen).map { look(for: $0) == .frosted } ?? false
    }

    /// Repaints each island in place, follows the palette's display and lists displays for Settings.
    private func applyLooks() {
        let available = screens
        let displays = available.map {
            IslandLookDisplay(displayID: $0.islandDisplayID, uuid: $0.islandDisplayUUID, name: $0.localizedName,
                              hasNotch: IslandLayout.notch(on: $0) != .zero)
        }
        if looks.displays != displays { looks.displays = displays }
        for screen in available { backdrops[screen.islandDisplayID]?.canvas.look = look(for: screen) }
        let palette = active?.canvas.look ?? .black
        if looks.palette != palette { looks.palette = palette }
        (core.islandPresenter as? IslandPresenter)?.looksChanged()
    }

    private func observeLooks() {
        withObservationTracking {
            _ = looks.choices
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeLooks()
                self.applyLooks()
            }
        }
    }

    private func observeVisibility() {
        withObservationTracking {
            _ = core.palette.isVisible
            _ = core.settings.animationsEnabled
            _ = core.isShowingDialog
            _ = core.settings.islandOpensOnHover
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeVisibility()
                self.hover.refresh()
                if self.core.palette.isVisible { self.active?.opened() } else { self.active?.closed() }
                if !self.core.palette.isVisible { self.applyCaptureSharing() }
            }
        }
    }

    isolated deinit {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        spaceCheck?.cancel()
    }
}
