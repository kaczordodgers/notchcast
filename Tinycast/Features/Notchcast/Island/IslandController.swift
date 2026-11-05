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
    private(set) var page = IslandPage.home
    var openContent = AnyView(Color.clear.frame(height: NotchcastTheme.estimatedContentHeight)) {
        didSet { updateOpenContent() }
    }
    /// What every panel shows closed; the view lays it out for its own shape.
    var closedState = IslandClosedState() {
        didSet { if closedState != oldValue { panels.forEach { $0.setClosed(closedState) } } }
    }
    /// The last cover decoded, keyed by its bytes, so a tick of the track never decodes it again.
    @ObservationIgnored private var artwork: (data: Data, image: NSImage)?
    /// The palette grown from the island, on one panel, while it is up.
    @ObservationIgnored private weak var launcherPanel: IslandPanel?
    /// The pinned page the launcher grew over, reopened pinned when it shrinks back.
    @ObservationIgnored private var pinnedUnderLauncher: IslandPage?

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
        setCommandAvailable = { [weak self, weak core] available in
            self?.commandsAvailable = available
            core?.appIndex.refreshNotchcastCommands()
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
        observeLauncher(identity: identity)
    }

    /// The palette summoned with Launcher from Island on: the island grows into its frame first and reports where.
    /// The palette's own hide shrinks it back (`observeLauncher`).
    func growLauncher(on screen: NSScreen, collapsed: Bool) -> CGRect? {
        guard observationID != nil, NotchcastPreferences.shared.isOn(.island),
              let panel = panels.first(where: { $0.displayFrame == screen.frame }),
              panel.isVisible, panel.isOnActiveSpace else { return nil }
        if isOpen { pinnedUnderLauncher = isPinned ? page : nil; close() }
        if launcherPanel !== panel { launcherPanel?.setLauncher(height: nil, animated: true) }
        launcherPanel = panel
        let height = collapsed ? Theme.Size.compactHeight : NotchcastTheme.Launcher.size.height
        panel.setLauncher(height: height, animated: true)
        return panel.launcherFrame
    }

    private func shrinkLauncher() {
        launcherPanel?.setLauncher(height: nil, animated: true)
        launcherPanel = nil
        if let page = pinnedUnderLauncher {
            pinnedUnderLauncher = nil
            open(page: page, takeKey: false)
            input.setPinned(true)
        }
    }

    private func observeLauncher(identity: UUID) {
        let core = AppCore.shared
        withObservationTracking {
            _ = core.palette.isVisible
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, observationID == identity else { return }
                if !core.palette.isVisible { shrinkLauncher() }
                observeLauncher(identity: identity)
            }
        }
    }

    func stop() {
        NotchcastCore.levelKeys.hudPresenterAvailable = false
        IslandActivityCenter.shared.hasPresenter = false
        close()
        pinnedUnderLauncher = nil
        shrinkLauncher()
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

    func open(page: IslandPage, on screen: NSScreen? = nil, takeKey: Bool = true) {
        guard observationID != nil, NotchcastPreferences.shared.isOn(.island) else { return }
        let point = screen.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? NSEvent.mouseLocation
        guard let index = IslandGeometry.panelIndex(containing: point, frames: panels.map(\.displayFrame),
                                                    visible: panels.map(\.isVisible)) else { return }
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
        if isOpen { close() } else { open(page: page) }
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

    /// Screen parameters also change on wake and Dock moves; same displays keep their panels and state.
    private func rebuildPanels() {
        let screens = NSScreen.screens
        guard panels.map(\.displayFrame) != screens.map(\.frame)
            || panels.map(\.hardwareNotch) != screens.map(IslandPanel.hardwareNotch(on:)) else {
            applyPreferences()
            return
        }
        let previousFrame = openPanel?.displayFrame
        let grown = launcherPanel.flatMap { panel in panel.launcherFrame.map { (panel.displayFrame, $0.height) } }
        panels.forEach { $0.close() }
        openPanel = nil
        launcherPanel = nil
        panels = screens.map(IslandPanel.init(screen:))
        for panel in panels {
            panel.onOpen = { [weak self, weak panel] in
                guard let self, let panel else { return }
                open(page: page, on: panel.screen)
            }
            panel.onKey = { [weak self] in self?.handleKey($0) ?? false }
            panel.onFocus = { [weak self] in self?.hasKeyboardFocus = $0 }
            panel.setClosed(closedState)
        }
        updateOpenContent()
        applyPreferences()
        if let grown, let panel = panels.first(where: { $0.displayFrame == grown.0 && $0.isVisible }) {
            launcherPanel = panel
            panel.setLauncher(height: grown.1, animated: false)
        }
        if isOpen, let panel = panels.first(where: { $0.displayFrame == previousFrame && $0.isVisible }) {
            openPanel = panel
            panel.setOpen(true, animated: false)
        } else { close() }
    }

    private func updateOpenContent() {
        for panel in panels {
            let header: AnyView
            if let pages {
                header = AnyView(IslandHeaderView(cameraWidth: panel.hardwareNotch?.width ?? 0,
                                                 height: panel.headerHeight)
                    .environment(self).environment(pages))
            } else {
                header = AnyView(Color.clear)
            }
            panel.setOpenContent(openContent, header: header)
        }
    }

    /// The playing song as the closed island shows it, nil while nothing plays or the song feed is off.
    private func music() -> IslandClosedState.Music? {
        guard NotchcastPreferences.shared.isOn(.musicNowPlaying),
              let track = NotchcastCore.services?.music.model.nowPlaying else { return nil }
        var cover: NSImage?
        if let data = track.artwork {
            if artwork?.data != data { artwork = NSImage(data: data).map { (data, $0) } }
            cover = artwork?.image
        }
        return .init(title: track.title, artist: track.artist, artwork: cover, isPlaying: track.isPlaying)
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
        let live = preferences.isOn(.islandLiveActivities)
        closedState = IslandClosedState.resolve(activities: live ? center.activities : [], music: music())
        let message = preferences.isOn(.islandStatusMessages) ? center.message : nil
        panels.forEach {
            $0.setMessage(message)
            $0.setActivityAccessibility(closedState.primary)
        }
        updatePresenter()
    }

    private func updatePresenter() {
        let active = panels.first { $0.displayFrame.contains(NSEvent.mouseLocation) }
        let eligible = IslandPresenterPolicy.shouldRegister(
            running: observationID != nil,
            enabled: NotchcastPreferences.shared.isOn(.islandStatusMessages),
            visibleOnActiveScreen: active?.isVisible == true && active?.isOnActiveSpace == true)
        IslandActivityCenter.shared.hasPresenter = eligible
        NotchcastCore.levelKeys.hudPresenterAvailable = eligible
            && NotchcastPreferences.shared.isOn(.islandLiveActivities)
    }

    private func observePreferences(identity: UUID) {
        withObservationTracking {
            let preferences = NotchcastPreferences.shared
            _ = preferences.isOn(.islandExternalDisplays)
            _ = preferences.isOn(.islandFullScreen)
            _ = preferences.isOn(.islandHoverOpen)
            _ = preferences.isOn(.islandLiveActivities)
            _ = preferences.isOn(.islandStatusMessages)
            _ = preferences.isOn(.musicNowPlaying)
            _ = IslandActivityCenter.shared.activities
            _ = IslandActivityCenter.shared.message
            _ = NotchcastCore.services?.music.model.nowPlaying
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
        guard isOpen, let key = IslandKey(event: event) else { return false }
        return pages?.perform(key, in: self) ?? false
    }
}
