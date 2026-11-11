import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class IslandController: NotchcastModule {
    static let shared = IslandController()

    private var input = IslandInputState()
    var isOpen: Bool { input.isOpen }
    var isPinned: Bool { input.isPinned }
    private(set) var commandsAvailable = false
    private(set) var hasKeyboardFocus = false
    var hasLiveActivities = false
    /// A song that stands in for Now Playing; set only by the Debug build's live demo.
    var demoTrack: IslandTrack?
    private(set) var page = IslandPage.home
    var openContent = AnyView(Color.clear.frame(height: NotchcastTheme.estimatedContentHeight)) {
        didSet { updateContent() }
    }
    /// What every panel shows closed; each shape lays it out itself.
    var closedState = IslandClosedState.idle {
        didSet { updateContent() }
    }

    @ObservationIgnored private(set) var panels: [IslandPanel] = []
    @ObservationIgnored var launcherObservations: [NotificationToken] = []
    @ObservationIgnored private(set) weak var openPanel: IslandPanel?
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
        core.hotKeys.seedIslandToggle(commandID: Self.launcherCommand.entry.id,
                                      marker: NotchcastPreferences.shared.engineDefaults)
        let pages = IslandPagesCoordinator(core: core, island: self)
        self.pages = pages
        openContent = AnyView(IslandPagesView().environment(self).environment(pages).environment(core.palette))
        setCommandAvailable = { [weak self] available in
            self?.commandsAvailable = available
            NotchcastHost.current.refreshNotchcastCommands()
        }
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
        watchLauncher()
    }

    func stop() {
        IslandActivityCenter.shared.hasPresenter = false
        close()
        setCommandAvailable(false)
        observationID = nil
        screenObservation = nil
        appObservation = nil
        spaceObservation = nil
        launcherObservations.removeAll()
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    func open(page: IslandPage, on screen: NSScreen? = nil, takeKey: Bool = true) {
        guard observationID != nil, NotchcastPreferences.shared.isOn(.island) else { return }
        restoreAfterLauncher()
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
        guard !isOpen else { return close() }
        // Opened on purpose: only Escape or the command again closes it.
        open(page: page)
        input.setPinned(true)
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
                guard let self, let panel, !launcherIsUp else { return }
                open(page: page, on: panel.screen)
            }
            panel.onKey = { [weak self] in self?.handleKey($0) ?? false }
            panel.onFocus = { [weak self] in self?.hasKeyboardFocus = $0 }
            panel.onPointer = { [weak self] in self?.pointerEvent($0) }
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
            panel.setContent(open: openContent, closed: closedState, header: header)
        }
    }

    private func applyPreferences() {
        let preferences = NotchcastPreferences.shared
        let externalDisplays = preferences.isOn(.islandExternalDisplays)
        let fullScreen = preferences.isOn(.islandFullScreen)
        for panel in panels {
            panel.fitCanvas()
            panel.setFullScreenEnabled(fullScreen)
            if panel.hardwareNotch != nil || externalDisplays {
                if !panel.isVisible { panel.orderFrontRegardless() }
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
        closedState = Self.closedState(
            message: preferences.showsStatusMessages ? center.message : nil,
            activities: preferences.isOn(.islandLiveActivities) ? center.ranked : [],
            track: demoTrack
                ?? (preferences.isEnabled(.musicNowPlaying) ? Self.track(MusicNowPlayingModule.shared?.model.nowPlaying) : nil))
        updatePresenter()
    }

    private func updatePresenter() {
        let active = panels.first { $0.displayFrame.contains(NSEvent.mouseLocation) }
        let eligible = IslandPresenterPolicy.shouldRegister(
            running: observationID != nil,
            enabled: NotchcastPreferences.shared.showsStatusMessages,
            visibleOnActiveScreen: active?.isVisible == true && active?.isOnActiveSpace == true)
        IslandActivityCenter.shared.hasPresenter = eligible
    }

    private func observePreferences(identity: UUID) {
        withObservationTracking {
            let preferences = NotchcastPreferences.shared
            _ = preferences.isOn(.islandExternalDisplays)
            _ = preferences.isOn(.islandFullScreen)
            _ = preferences.isOn(.islandHoverOpen)
            _ = preferences.isOn(.islandLiveActivities)
            _ = preferences.showsStatusMessages
            _ = IslandActivityCenter.shared.activities
            _ = IslandActivityCenter.shared.message
            _ = preferences.isEnabled(.musicNowPlaying)
            _ = MusicNowPlayingModule.shared?.model.nowPlaying
            _ = demoTrack
            _ = NotchcastTheme.Launcher.size
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, observationID == identity else { return }
                observePreferences(identity: identity)
            }
        }
        applyPreferences()
        setCommandAvailable(true)
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
                      hoverEnabled: preferences.isOn(.islandHoverOpen) && !launcherIsUp,
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
