import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class IslandController: NotchcastModule, IslandActivityPresenter {
    struct ClosedContent {
        var leading: AnyView?
        var trailing: AnyView?
    }

    static let shared = IslandController()

    private var input = IslandInputState()
    var isOpen: Bool { input.isOpen }
    var isPinned: Bool { input.isPinned }
    private(set) var hasKeyboardFocus = false
    var hasLiveActivities = false
    private(set) var page = IslandPage.home
    var openContent = AnyView(Color.clear.frame(height: NotchcastTheme.estimatedContentHeight)) {
        didSet { updateContent() }
    }
    /// Builds each panel's wings or pill using its screen and notch geometry; views inherit the notch flag.
    var closedContent: (IslandClosedContext) -> ClosedContent = { _ in ClosedContent() } {
        didSet { updateContent() }
    }

    @ObservationIgnored private var panels: [IslandPanel] = []
    @ObservationIgnored private weak var openPanel: IslandPanel?
    @ObservationIgnored private var screenObservation: NotificationToken?
    @ObservationIgnored private var mouseMonitors: [Any] = []
    @ObservationIgnored private var observationID: UUID?
    @ObservationIgnored private var openedAt: TimeInterval = 0
    @ObservationIgnored private var appObservation: NotificationToken?
    @ObservationIgnored private var spaceObservation: NotificationToken?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var pages: IslandPagesCoordinator?
    @ObservationIgnored private var setCommandAvailable: (Bool) -> Void = { _ in }

    func configurePages(_ core: AppCore) {
        guard pages == nil else { return }
        let pages = IslandPagesCoordinator(core: core, island: self)
        self.pages = pages
        openContent = AnyView(IslandPagesView().environment(self).environment(pages).environment(core.palette))
        setCommandAvailable = { [weak core] in core?.appIndex.setCommandsVisible([.toggleIsland], $0) }
        setCommandAvailable(false)
    }

    func start() {
        guard observationID == nil else { return }
        let identity = UUID()
        observationID = identity
        let center = NotificationCenter.default
        screenObservation = NotificationToken(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, observationID == identity else { return }
                rebuildPanels()
            }
        }, center: center)
        watchPointer()
        watchApplications(identity: identity)
        let workspace = NSWorkspace.shared.notificationCenter
        spaceObservation = NotificationToken(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, observationID == identity else { return }
                updatePresenter()
            }
        }, center: workspace)
        rebuildPanels()
        setCommandAvailable(true)
        observePreferences(identity: identity)
    }

    func stop() {
        IslandActivityCenter.shared.presenter = nil
        close()
        setCommandAvailable(false)
        observationID = nil
        screenObservation = nil
        appObservation = nil
        spaceObservation = nil
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    func open(page: IslandPage, on screen: NSScreen? = nil, takeKey: Bool = false) {
        guard observationID != nil, NotchcastPreferences.shared.isOn(.island) else { return }
        let frames = panels.map(\.displayFrame)
        let point = screen.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? NSEvent.mouseLocation
        guard let index = IslandGeometry.screenIndex(containing: point, frames: frames),
              panels[index].isVisible else { return }
        let wasOpen = openPanel != nil && isOpen
        if openPanel !== panels[index] { openPanel?.setOpen(false, animated: true) }
        openPanel = panels[index]
        openedAt = ProcessInfo.processInfo.systemUptime
        let target = wasOpen ? page : page.landingPage(
            hasLiveActivities: hasLiveActivities && NotchcastPreferences.shared.isOn(.islandLiveActivities))
        let changedPage = self.page != target
        self.page = target
        input.open()
        hoverTask?.cancel()
        hoverTask = nil
        openPanel?.setOpen(true, animated: true)
        if !wasOpen || changedPage { pages?.didOpen(page: target) }
        if takeKey { openPanel?.makeKey() }
    }

    func close() {
        input.close()
        hoverTask?.cancel()
        hoverTask = nil
        pages?.didClose()
        openPanel?.setOpen(false, animated: true)
        openPanel = nil
        hasKeyboardFocus = false
    }

    func toggle() {
        if isOpen { close() } else { open(page: page, takeKey: true) }
    }

    func selectPage(_ page: IslandPage) {
        guard isOpen, self.page != page else { return }
        self.page = page
        pages?.didOpen(page: page)
    }

    func togglePin() {
        input.togglePin()
        if !isOpen { close() }
    }

    private func rebuildPanels() {
        let previousFrame = openPanel?.displayFrame
        panels.forEach { $0.close() }
        openPanel = nil
        panels = NSScreen.screens.map(IslandPanel.init(screen:))
        for panel in panels {
            panel.onOpen = { [weak self, weak panel] in
                guard let self, let panel else { return }
                open(page: page, on: panel.screen, takeKey: false)
            }
            panel.onKey = { [weak self] in self?.handleKey($0) ?? false }
            panel.onFocus = { [weak self] in self?.hasKeyboardFocus = $0 }
        }
        updateContent()
        applyPreferences()
        if isOpen, let panel = panels.first(where: { $0.displayFrame == previousFrame && $0.isVisible }) {
            openPanel = panel
            panel.setOpen(true, animated: false)
        } else { close() }
    }

    private func updateContent() {
        for panel in panels {
            let header: AnyView
            if let pages {
                header = AnyView(IslandHeaderView(cameraWidth: panel.hardwareNotch?.width ?? 0,
                                                 height: panel.headerHeight)
                    .environment(self).environment(pages))
            } else {
                header = AnyView(Color.clear)
            }
            panel.setContent(open: openContent, closed: closedContent(panel.closedContext), header: header)
        }
    }

    private func applyPreferences() {
        let preferences = NotchcastPreferences.shared
        let externalDisplays = preferences.isOn(.islandExternalDisplays)
        let fullScreen = preferences.isOn(.islandFullScreen)
        for panel in panels {
            panel.setFullScreenEnabled(fullScreen)
            if panel.hardwareNotch != nil || externalDisplays {
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
            panel.updateMousePassthrough()
        }
        if let openPanel, !openPanel.isVisible { close() }
        if !preferences.isOn(.islandHoverOpen) {
            input.cancelHoverOpen()
            scheduleHover()
        }
        let center = IslandActivityCenter.shared
        hasLiveActivities = !center.activities.isEmpty
        let activity = preferences.isOn(.islandLiveActivities) ? center.current : nil
        closedContent = { _ in ClosedContent(
            leading: activity.map { AnyView(IslandActivityGlyph(activity: $0)) },
            trailing: activity.map { AnyView(IslandActivityValue(activity: $0, multiple: center.activities.count > 1)) }) }
        let message = preferences.isOn(.islandStatusMessages) ? center.message : nil
        panels.forEach {
            $0.setMessage(message)
            $0.setActivityAccessibility(activity)
        }
        updatePresenter()
    }

    private func updatePresenter() {
        let active = panels.first { $0.displayFrame.contains(NSEvent.mouseLocation) }
        let eligible = IslandPresenterPolicy.shouldRegister(
            running: observationID != nil,
            enabled: NotchcastPreferences.shared.isOn(.islandStatusMessages),
            visibleOnActiveScreen: active?.isVisible == true && active?.isOnActiveSpace == true)
        IslandActivityCenter.shared.presenter = eligible ? self : nil
    }

    private func observePreferences(identity: UUID) {
        withObservationTracking {
            let preferences = NotchcastPreferences.shared
            _ = preferences.isOn(.islandExternalDisplays)
            _ = preferences.isOn(.islandFullScreen)
            _ = preferences.isOn(.islandHoverOpen)
            _ = preferences.isOn(.islandLiveActivities)
            _ = preferences.isOn(.islandStatusMessages)
            _ = IslandActivityCenter.shared.activities
            _ = IslandActivityCenter.shared.message
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, observationID == identity else { return }
                observePreferences(identity: identity)
            }
        }
        applyPreferences()
    }

    private func watchPointer() {
        // The global pointer monitor is the deliberate M0 hook for island hit-region tracking.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                             .otherMouseDragged, .leftMouseDown, .rightMouseDown,
                                             .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.pointerEvent(event)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.pointerEvent(event)
            return event
        }
        mouseMonitors = [global, local].compactMap { $0 }
    }

    private func pointerEvent(_ event: NSEvent) {
        updatePresenter()
        panels.forEach { $0.updateMousePassthrough() }
        let inside = isOpen ? openPanel?.containsPointer == true
            : panels.contains { $0.isVisible && $0.containsPointer }
        let preferences = NotchcastPreferences.shared
        let previousHover = input.pendingHover
        input.pointer(inside: inside, now: ProcessInfo.processInfo.systemUptime,
                      hoverEnabled: preferences.isOn(.islandHoverOpen),
                      delay: preferences.islandHoverDelay.rawValue)
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type), !inside {
            dismiss(.outsideClick)
        }
        if previousHover != input.pendingHover { scheduleHover() }
    }

    private func scheduleHover() {
        hoverTask?.cancel()
        hoverTask = nil
        guard let pending = input.pendingHover, let identity = observationID else { return }
        hoverTask = Task { [weak self] in
            let remaining = max(0, pending.deadline - ProcessInfo.processInfo.systemUptime)
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self, observationID == identity,
                  input.pendingHover == pending else { return }
            let action = input.advance(now: ProcessInfo.processInfo.systemUptime, focused: hasKeyboardFocus)
            switch action {
            case .open:
                input.close()
                if NotchcastPreferences.shared.isOn(.islandHoverOpen) {
                    open(page: page, takeKey: false)
                }
            case .close: close()
            case nil: break
            }
        }
    }

    private func dismiss(_ reason: IslandInputState.Dismissal) {
        input.dismiss(reason, focused: hasKeyboardFocus)
        if !isOpen { close() }
    }

    private func watchApplications(identity: UUID) {
        let center = NSWorkspace.shared.notificationCenter
        appObservation = NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard application?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            let switchedAt = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self, observationID == identity, openedAt <= switchedAt else { return }
                dismiss(.appSwitch)
            }
        }, center: center)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isOpen else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            if event.isARepeat { return key == "p" || key == "r" || IslandPage.page(forKey: key) != nil }
            if key == "p" { togglePin(); return true }
            if key == "r" { pages?.refresh(page); return true }
            if let target = IslandPage.page(forKey: key) {
                if target == page { dismiss(.pageKey) } else { selectPage(target) }
                return true
            }
        }
        if flags.isEmpty {
            switch event.keyCode {
            case 53: dismiss(.escape)
            case 123: pages?.moveHeader(-1)
            case 124: pages?.moveHeader(1)
            case 125: pages?.moveSelection(1, page: page)
            case 126: pages?.moveSelection(-1, page: page)
            case 36, 76: pages?.activateHeader(in: self)
            case 48: pages?.moveHeader(1)
            default: return false
            }
            return true
        }
        if flags == .shift, event.keyCode == 48 { pages?.moveHeader(-1); return true }
        return false
    }
}
